import 'package:flutter/foundation.dart';

import '../../../data/models/requisition.dart';
import '../../../data/repositories/requisition_repository.dart';
import '../../../data/services/requisition_service.dart';

/// The Store Manager's approve/reject queue.
///
/// Decision 09 put POS in charge of the **downstream** half of the requisition lifecycle, and this
/// viewmodel is the half of that which is not a counter: approving and rejecting what CPMS sent.
///
/// Two rules here are load-bearing and are tested below the widget rather than through it:
///
/// * **Only a `SUBMITTED` row carries an action.** The server refuses an illegal transition with a
///   bare `ValueError`, which reaches the UI as prose indistinguishable from a bug, so the client
///   must not offer what the server will refuse.
/// * **The server's own refusal is shown verbatim.** Those same guards name the reason
///   ("Cannot approve a DRAFT requisition."); replacing that with a generic message destroys the
///   only explanation the manager gets for a button that did nothing.
class AdminRequisitionsViewmodel extends ChangeNotifier {
  AdminRequisitionsViewmodel({RequisitionRepository? repository})
    : _repository = repository ?? RequisitionRepository();

  final RequisitionRepository _repository;

  bool isLoading = false;

  /// Why the queue could not be loaded. Kept separate from [actionError]: "we could not read the
  /// list" and "that one approval was refused" are different situations and need different words.
  String? loadError;

  /// Why the last approve/reject did nothing.
  String? actionError;

  List<Requisition> requisitions = const [];

  /// Rows the server will actually accept an action on.
  ///
  /// A status this client was never taught is deliberately **not** pending: it stays in
  /// [requisitions] so a server that adds a status cannot make the queue silently shorter, but it
  /// gets no button, because approving a state we cannot name is guessing.
  List<Requisition> get pending => requisitions
      .where((row) => row.status.isAwaitingApproval)
      .toList(growable: false);

  Future<void> load() async {
    isLoading = true;
    loadError = null;
    notifyListeners();
    try {
      requisitions = await _repository.fetchRequisitions();
    } on RequisitionServiceException catch (error) {
      // The rows already fetched are still real; emptying the list would read as "nothing is
      // awaiting approval", which is a claim we cannot make.
      loadError = error.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// Returns true only if the server accepted the approval.
  Future<bool> approve(int requisitionId) => _act(
    requisitionId,
    (id) => _repository.approve(id),
    RequisitionStatus.approved,
  );

  /// Returns true only if the server accepted the rejection.
  Future<bool> reject(int requisitionId) => _act(
    requisitionId,
    (id) => _repository.reject(id),
    RequisitionStatus.rejected,
  );

  Future<bool> _act(
    int requisitionId,
    Future<void> Function(int id) call,
    RequisitionStatus result,
  ) async {
    // A second press while the first is in flight must send NOTHING. Without this the row is still
    // SUBMITTED (the replacement only happens after the await), so both presses reached the server;
    // the real one 400s the second, and the manager saw a refusal for an action that SUCCEEDED.
    if (isLoading) return false;

    final row = _rowFor(requisitionId);
    if (row == null || !row.status.isAwaitingApproval) return false;

    actionError = null;
    isLoading = true;
    notifyListeners();
    try {
      await call(requisitionId);
    } on RequisitionServiceException catch (error) {
      actionError = error.message;
      notifyListeners();
      return false;
    } finally {
      isLoading = false;
    }

    _replace(row, result);
    notifyListeners();
    return true;
  }

  Requisition? _rowFor(int id) {
    for (final row in requisitions) {
      if (row.id == id) return row;
    }
    return null;
  }

  /// [Requisition] is immutable, so a served action is reflected by replacing the row with a copy
  /// carrying the new status. The alternative — re-fetching the list — would make the manager wait
  /// on a round trip to see the effect of a call that already answered.
  void _replace(Requisition old, RequisitionStatus status) {
    requisitions = [
      for (final row in requisitions)
        if (identical(row, old))
          Requisition(
            id: row.id,
            reqNumber: row.reqNumber,
            rawStatus: status.apiValue,
            projectName: row.projectName,
            projectCustomerName: row.projectCustomerName,
            requestedByName: row.requestedByName,
            items: row.items,
            token: row.token,
          )
        else
          row,
    ];
  }
}
