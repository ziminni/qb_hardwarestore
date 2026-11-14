import 'package:client/data/models/cheque.dart';
import 'package:client/data/services/cheque_service.dart';
import 'package:flutter/foundation.dart';

/// The Store Manager's cheque queue (Phase 4 task F5, decision 18).
///
/// Screen-scoped and provided by its page, like [SalesReceivablesViewmodel]: a
/// viewmodel that lives as long as one screen should not outlive it.
///
/// Two rules it exists to hold:
///  * **pending first, oldest first.** The queue exists to chase money, so the
///    cheque at risk is at the top. A newest-first list buries it.
///  * **the server decides, the screen re-reads.** A decision always reloads
///    rather than editing the row locally, and a 409 conflict reloads too, so the
///    table can never show a PENDING row the server has already settled.
///    Clearing twice would pay a debt nobody paid.
class ChequeQueueViewmodel extends ChangeNotifier {
  ChequeQueueViewmodel({ChequeService? service})
    : _service = service ?? ChequeService();

  final ChequeService _service;

  List<Cheque> _cheques = const [];
  bool _isLoading = false;
  String? _loadError;
  final Set<int> _decidingIds = {};
  String? _decisionError;

  /// Null shows every cheque. Set, the rows narrow to that status; the pending
  /// count on the tab keeps reading the whole list either way.
  ChequeStatus? _statusFilter;
  ChequeStatus? get statusFilter => _statusFilter;

  /// Every cheque, pending first and then oldest cheque date first.
  List<Cheque> get cheques {
    final rows = [..._cheques];
    rows.sort((a, b) {
      // Pending before decided.
      if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
      final byDate = a.chequeDate.compareTo(b.chequeDate);
      if (byDate != 0) return byDate;
      // A stable tail, so two cheques written the same day keep one order.
      return a.id.compareTo(b.id);
    });
    return List.unmodifiable(rows);
  }

  List<Cheque> get filteredCheques {
    final filter = _statusFilter;
    if (filter == null) return cheques;
    return List.unmodifiable(
      cheques.where((cheque) => cheque.status == filter),
    );
  }

  /// How many cheques the shop is still waiting on: the tab marker.
  int get pendingCount => _cheques.where((cheque) => cheque.isPending).length;

  bool get isLoading => _isLoading;
  String? get loadError => _loadError;
  bool get hasCheques => _cheques.isNotEmpty;

  /// Why the last decision failed; null when it succeeded or none ran.
  String? get decisionError => _decisionError;

  /// True while a decision on [chequeId] is in flight, so its buttons stay
  /// disabled and a double tap cannot send a second decision.
  bool isDeciding(int chequeId) => _decidingIds.contains(chequeId);

  void setStatusFilter(ChequeStatus? status) {
    _statusFilter = status;
    notifyListeners();
  }

  /// Loads every cheque.
  ///
  /// A failed load keeps the rows already shown: emptying the table would read
  /// as "no cheques to chase", which a failed read has not established.
  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      _cheques = await _service.fetchCheques();
    } on ChequeServiceException catch (error) {
      _loadError = error.message;
    } catch (_) {
      _loadError = 'The cheque queue could not be loaded.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> clear(Cheque cheque) =>
      _decide(cheque, () => _service.clear(cheque.id));

  Future<bool> bounce(Cheque cheque, String reason) {
    if (reason.trim().isEmpty) {
      // The server refuses this with CHEQUE_REASON_REQUIRED; refusing it here
      // too keeps a pointless round trip off the queue and says the same thing.
      _decisionError =
          'A bounced cheque needs a reason. Write down why the bank refused it.';
      notifyListeners();
      return Future.value(false);
    }
    return _decide(cheque, () => _service.bounce(cheque.id, reason));
  }

  Future<bool> _decide(Cheque cheque, Future<Cheque> Function() send) async {
    if (_decidingIds.contains(cheque.id)) return false;
    if (!cheque.isPending) {
      // Clearing twice would pay the ledger twice. The row on screen is stale.
      _decisionError =
          '${cheque.chequeNumber} is already ${cheque.status.label.toLowerCase()} and cannot be decided again.';
      notifyListeners();
      return false;
    }
    _decidingIds.add(cheque.id);
    _decisionError = null;
    notifyListeners();
    try {
      await send();
      // The server owns the ledger movement and the row's new status, so the
      // queue is re-read rather than patched locally.
      await load();
      if (_loadError != null) {
        // The decision landed but the rows did not refresh. Claiming success
        // would close the dialog over stale rows; claiming a plain failure would
        // invite a retry that the server answers 409.
        _decisionError =
            'The decision was recorded, but the queue could not be refreshed. Reload before deciding again.';
        return false;
      }
      return true;
    } on ChequeServiceException catch (error) {
      _decisionError = error.message;
      if (error.alreadyDecided) {
        // The server says this cheque is settled: the rows must stop saying
        // PENDING before the manager reads them again.
        await load();
      }
      return false;
    } finally {
      _decidingIds.remove(cheque.id);
      notifyListeners();
    }
  }
}
