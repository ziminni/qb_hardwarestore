import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/data/services/ledger_service.dart';
import 'package:flutter/foundation.dart';

/// Owns the receivables screen's data: the real collectibles ledger.
///
/// Screen-scoped and provided by its own page rather than registered in `main.dart`, matching
/// decision 11's ruling for `PosTransactionViewmodel` and `ProductsViewmodel` - a viewmodel
/// that lives as long as one screen should not outlive it.
class SalesReceivablesViewmodel extends ChangeNotifier {
  SalesReceivablesViewmodel({LedgerRepository? repository})
    : _repository = repository ?? LedgerRepository();

  final LedgerRepository _repository;

  List<LedgerEntry> _entries = const [];
  bool _isLoading = false;
  String? _loadError;
  final Set<int> _payingIds = {};
  String? _payError;

  List<LedgerEntry> get entries => List.unmodifiable(_entries);
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  /// Null shows every row. Set, rows narrow to that status via `statusAt` —
  /// the same source the tiles use, so the Overdue tile and an Overdue chip
  /// cannot disagree about which debts are late.
  LedgerStatus? _statusFilter;
  LedgerStatus? get statusFilter => _statusFilter;

  List<LedgerEntry> get filteredEntries {
    final filter = _statusFilter;
    if (filter == null) return List.unmodifiable(_entries);
    final now = DateTime.now();
    return List.unmodifiable(
      _entries.where((entry) => entry.statusAt(now) == filter),
    );
  }

  void setStatusFilter(LedgerStatus? status) {
    _statusFilter = status;
    notifyListeners();
  }

  /// Total still owed across every open receivable.
  double get outstanding =>
      _entries.fold<double>(0, (sum, entry) => sum + entry.balanceDue);

  /// The part of [outstanding] that the server or the due date calls overdue.
  ///
  /// Computed with the terminal's clock via `statusAt`, the same source the rows use, so the
  /// tile and the rows cannot disagree about which debts are late.
  double get overdue {
    final now = DateTime.now();
    return _entries
        .where((entry) => entry.statusAt(now) == LedgerStatus.overdue)
        .fold<double>(0, (sum, entry) => sum + entry.balanceDue);
  }

  bool get hasEntries => _entries.isNotEmpty;

  /// Ledgers with a payment currently in flight — their row buttons stay disabled
  /// so a double tap cannot post twice.
  bool isPaying(int ledgerId) => _payingIds.contains(ledgerId);

  /// Why the last payment failed; null when the last payment succeeded or none ran.
  String? get payError => _payError;

  /// Posts one payment against [entry], then reloads from the server.
  ///
  /// Reloads rather than subtracting locally: the server owns `balance_due` and the
  /// refusal semantics, so the rows must show what it says, not what the till assumed.
  /// Returns false without touching the repository when the amount is not payable.
  Future<bool> recordPayment({
    required LedgerEntry entry,
    required double amount,
  }) async {
    if (_payingIds.contains(entry.id)) return false;
    if (amount <= 0) {
      _payError = 'Enter an amount greater than zero.';
      notifyListeners();
      return false;
    }
    if (amount > entry.balanceDue) {
      _payError =
          'That payment is more than the ${entry.balanceDue.toStringAsFixed(2)} still owed.';
      notifyListeners();
      return false;
    }
    _payingIds.add(entry.id);
    _payError = null;
    notifyListeners();
    try {
      await _repository.recordPayment(
        collectibleId: entry.id,
        amountPaid: amount,
      );
      await load();
      if (_loadError != null) {
        // The money moved but the rows did not refresh. Returning true would pop
        // the dialog over stale balances; returning a plain failure would invite a
        // retry that double-posts a partial payment. Neither claim is honest, so
        // the dialog stays open naming exactly what happened.
        _payError =
            'Payment was recorded, but the list could not be refreshed. Close and check before posting again.';
        return false;
      }
      return true;
    } on LedgerServiceException catch (error) {
      _payError = error.message;
      return false;
    } finally {
      _payingIds.remove(entry.id);
      notifyListeners();
    }
  }

  /// Loads every open receivable.
  ///
  /// A failed load sets [loadError] but KEEPS the entries already shown: emptying the table
  /// would read as "this store is owed nothing", which is a different and far more dangerous
  /// statement than "this did not load".
  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();

    try {
      _entries = await _repository.fetchLedgers();
      _loadError = null;
    } on LedgerServiceException catch (error) {
      _loadError = error.message;
    } catch (error) {
      // Anything else (a malformed body, a transport error the service did not map) still
      // has to become something a cashier can read.
      _loadError = 'The receivables could not be loaded.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
