import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/ledger_service.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter/foundation.dart';

/// The two counts the Store Manager dashboard cannot fold from its own rows:
/// requisitions waiting for approval and receivables already past due.
///
/// Both reads walk EVERY page (`RequisitionService` and `LedgerService` page
/// through the list), so the number on a tile is the whole queue, not the first
/// fifty rows of it.
///
/// Screen-scoped and built by its page, like [SalesReceivablesViewmodel]: a
/// viewmodel that lives as long as one screen should not outlive it.
class SalesDashboardAlertsViewmodel extends ChangeNotifier {
  SalesDashboardAlertsViewmodel({
    RequisitionRepository? requisitions,
    LedgerRepository? ledgers,
  }) : _requisitions = requisitions ?? RequisitionRepository(),
       _ledgers = ledgers ?? LedgerRepository();

  final RequisitionRepository _requisitions;
  final LedgerRepository _ledgers;

  /// Null until a complete read has answered. A failed read leaves it null, so
  /// the tile says "Not loaded" instead of a zero nobody counted.
  int? _awaitingApprovals;
  int? _overdueReceivables;
  String? _loadError;

  int? get awaitingApprovals => _awaitingApprovals;
  int? get overdueReceivables => _overdueReceivables;

  /// The first failure, for the banner. Counts that did answer stay on screen:
  /// one dead read must not blank the other tile.
  String? get loadError => _loadError;

  static const String _unknownFailure =
      'The dashboard counts could not be loaded. Try again.';

  /// Reads both queues, each in its own try, so one failure cannot hide the
  /// other count.
  Future<void> load() async {
    String? failure;
    try {
      final rows = await _requisitions.fetchRequisitions();
      _awaitingApprovals = rows
          .where((row) => row.status.isAwaitingApproval)
          .length;
    } on RequisitionServiceException catch (error) {
      failure ??= error.message;
    } catch (_) {
      // Boundary: an uninitialised client or a shape the parser did not expect
      // must leave the tile saying "Not loaded", never take the dashboard down.
      failure ??= _unknownFailure;
    }

    try {
      final rows = await _ledgers.fetchLedgers();
      final now = appClock.now();
      _overdueReceivables = rows
          .where((row) => row.statusAt(now) == LedgerStatus.overdue)
          .length;
    } on LedgerServiceException catch (error) {
      failure ??= error.message;
    } catch (_) {
      failure ??= _unknownFailure;
    }

    _loadError = failure;
    notifyListeners();
  }
}
