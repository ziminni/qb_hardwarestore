import 'package:client/data/models/requisition.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:client/features/admin/viewmodels/admin_requisitions_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

/// The approve/reject queue's rules, pinned BELOW the widget.
///
/// Decision 09 gives the Store Manager two actions and one prohibition: the UI must not offer an
/// action the server's status guard would refuse, because a bare `ValueError` reaching the counter
/// is indistinguishable from a bug. That rule is a rule about the viewmodel, so it is tested here —
/// a widget test would pin the button's `onPressed` and say nothing about whether the call is made.
class _StubRequisitions extends RequisitionRepository {
  _StubRequisitions(this.rows);

  final List<Requisition> rows;
  int fetchCalls = 0;
  final List<int> approved = [];
  final List<int> rejected = [];
  Object? failFetch;
  Object? failApprove;

  @override
  Future<List<Requisition>> fetchRequisitions() async {
    fetchCalls++;
    if (failFetch != null) throw failFetch!;
    return rows;
  }

  @override
  Future<String> approve(int requisitionId) async {
    if (failApprove != null) throw failApprove!;
    approved.add(requisitionId);
    return 'token-$requisitionId';
  }

  @override
  Future<void> reject(int requisitionId) async {
    rejected.add(requisitionId);
  }
}

Requisition _req(int id, String status) => Requisition(
  id: id,
  reqNumber: 'REQ-000$id',
  rawStatus: status,
  projectName: '2-Storey House - Mandaue',
  projectCustomerName: 'Dela Cruz Construction',
  requestedByName: 'Fore Man',
  items: const [],
  token: null,
);

void main() {
  group('AdminRequisitionsViewmodel', () {
    test('load brings the queue in and clears the loading flag', () async {
      final repo = _StubRequisitions([_req(1, 'SUBMITTED'), _req(2, 'DRAFT')]);
      final vm = AdminRequisitionsViewmodel(repository: repo);

      await vm.load();

      expect(vm.isLoading, isFalse);
      expect(vm.loadError, isNull);
      expect(vm.requisitions, hasLength(2));
      expect(repo.fetchCalls, 1);
    });

    test('a FAILED load reports the error and does not claim the queue is empty', () async {
      // An emptied list reads as "no requisitions awaiting approval" — a manager would stop looking.
      final repo = _StubRequisitions([_req(1, 'SUBMITTED')]);
      final vm = AdminRequisitionsViewmodel(repository: repo);
      await vm.load();

      repo.failFetch = RequisitionServiceException('The requisitions could not be loaded.');
      await vm.load();

      expect(vm.loadError, 'The requisitions could not be loaded.');
      expect(vm.requisitions, hasLength(1), reason: 'the rows already fetched are still real');
    });

    test('only a SUBMITTED row is approvable — the other statuses send nothing', () async {
      final repo = _StubRequisitions([
        _req(1, 'DRAFT'),
        _req(2, 'APPROVED'),
        _req(3, 'RELEASED'),
        _req(4, 'REJECTED'),
      ]);
      final vm = AdminRequisitionsViewmodel(repository: repo);
      await vm.load();

      for (final id in [1, 2, 3, 4]) {
        expect(await vm.approve(id), isFalse, reason: 'row $id must not be approvable');
      }
      expect(repo.approved, isEmpty);
    });

    test('approving a SUBMITTED row calls the repository and it leaves the pending set', () async {
      final repo = _StubRequisitions([_req(1, 'SUBMITTED'), _req(2, 'SUBMITTED')]);
      final vm = AdminRequisitionsViewmodel(repository: repo);
      await vm.load();
      expect(vm.pending, hasLength(2));

      expect(await vm.approve(1), isTrue);

      expect(repo.approved, [1]);
      expect(vm.pending.map((r) => r.id), [2]);
    });

    test('rejecting a SUBMITTED row calls the repository and it leaves the pending set', () async {
      final repo = _StubRequisitions([_req(1, 'SUBMITTED')]);
      final vm = AdminRequisitionsViewmodel(repository: repo);
      await vm.load();

      expect(await vm.reject(1), isTrue);

      expect(repo.rejected, [1]);
      expect(vm.pending, isEmpty);
    });

    test("the server's own refusal wins over the client's generic wording", () async {
      // The status guards refuse with prose that names the reason ("Cannot approve a DRAFT
      // requisition."). Replacing it with "something went wrong" destroys the only explanation
      // a Store Manager gets for a button that did nothing.
      final repo = _StubRequisitions([_req(1, 'SUBMITTED')]);
      final vm = AdminRequisitionsViewmodel(repository: repo);
      await vm.load();
      repo.failApprove = RequisitionServiceException('Cannot approve a DRAFT requisition.');

      expect(await vm.approve(1), isFalse);

      expect(vm.actionError, 'Cannot approve a DRAFT requisition.');
      expect(vm.pending, hasLength(1), reason: 'a refused approval must not remove the row');
    });

    test('a status the client was never taught is STILL SHOWN and is not approvable', () async {
      // A server that adds a status must not make the queue silently shorter.
      final repo = _StubRequisitions([_req(1, 'AWAITING_BUDGET')]);
      final vm = AdminRequisitionsViewmodel(repository: repo);

      await vm.load();

      expect(vm.requisitions, hasLength(1));
      expect(vm.requisitions.single.rawStatus, 'AWAITING_BUDGET');
      expect(vm.pending, isEmpty);
      expect(await vm.approve(1), isFalse);
      expect(repo.approved, isEmpty);
    });
  });
}
