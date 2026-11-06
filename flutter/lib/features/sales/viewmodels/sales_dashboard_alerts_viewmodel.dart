import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/data/services/ledger_service.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter/foundation.dart';

/// The count the Store Manager dashboard cannot fold from its own rows:
/// receivables already past due.
///
/// The read walks EVERY page (`LedgerService` pages through the list), so the
/// number on the tile is the whole book, not the first fifty rows of it. The
/// requisition queue that used to be counted here is gone (decision 01):
/// requests are approved in CPMS, so the POS has nothing to review.
///
/// Screen-scoped and built by its page, like [SalesReceivablesViewmodel]: a
/// viewmodel that lives as long as one screen should not outlive it.
class SalesDashboardAlertsViewmodel extends ChangeNotifier {
  SalesDashboardAlertsViewmodel({LedgerRepository? ledgers})
    : _ledgers = ledgers ?? LedgerRepository();

  final LedgerRepository _ledgers;

  /// Null until a complete read has answered. A failed read leaves it null, so
  /// the tile says "Not loaded" instead of a zero nobody counted.
  int? _overdueReceivables;
  String? _loadError;

  int? get overdueReceivables => _overdueReceivables;

  /// The first failure, for the banner.
  String? get loadError => _loadError;

  static const String _unknownFailure =
      'The dashboard counts could not be loaded. Try again.';

  /// Reads the overdue book. A failure leaves the tile saying "Not loaded"
  /// rather than a zero nobody counted.
  Future<void> load() async {
    String? failure;
    try {
      final rows = await _ledgers.fetchLedgers();
      final now = appClock.now();
      _overdueReceivables = rows
          .where((row) => row.statusAt(now) == LedgerStatus.overdue)
          .length;
    } on LedgerServiceException catch (error) {
      failure = error.message;
    } catch (_) {
      failure = _unknownFailure;
    }

    _loadError = failure;
    notifyListeners();
  }
}
