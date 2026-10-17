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

  List<LedgerEntry> get entries => List.unmodifiable(_entries);
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

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
