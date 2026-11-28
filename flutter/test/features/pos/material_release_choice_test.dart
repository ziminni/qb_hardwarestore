// The cashier chooses each line's Give now (2026-11-27 design). The viewmodel
// keeps the amount, clamps it to what can go out, and sends it with the release.

import 'package:client/data/models/requisition.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:client/features/pos/viewmodels/material_release_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

const _cement = VerifiedRequisitionItem(
  id: 1,
  variantId: 7,
  variantName: 'Portland Cement — 40kg',
  quantity: 10,
  remaining: 7,
  availability: LineAvailability.short,
  releasable: 4,
  unit: 'BAG',
  isWhole: true,
  unitPrice: 260,
);

const _wire = VerifiedRequisitionItem(
  id: 2,
  variantId: 8,
  variantName: 'Tie wire #16',
  quantity: 12.5,
  remaining: 12.5,
  availability: LineAvailability.full,
  releasable: 12.5,
  unit: 'KG',
  isWhole: false,
  unitPrice: 40,
);

class _Repo extends RequisitionRepository {
  _Repo();

  int verifyCalls = 0;
  Map<int, double>? sent;
  Object? failRelease;

  TokenVerification _verification() => TokenVerification(
    token: 'tok',
    requisitionId: 6,
    reqNumber: 'REQ-0006',
    project: 'Villanueva residence',
    customer: 'Dela Cruz Construction',
    status: 'PARTIAL',
    items: const [_cement, _wire],
  );

  @override
  Future<TokenVerification> verifyToken(String token) async {
    verifyCalls++;
    return _verification();
  }

  @override
  Future<TokenVerification> verifyRequest(int id) async {
    verifyCalls++;
    return _verification();
  }

  @override
  Future<ReleaseResult> release(
    String token, {
    Map<int, double>? quantities,
  }) async {
    sent = quantities;
    if (failRelease != null) throw failRelease!;
    return const ReleaseResult(
      transactionId: 1,
      transactionNo: 'TXN-1',
      status: ReleaseStatus.partial,
      items: [],
      grandTotal: 1240,
      ledgerId: 1,
      balanceDue: 1240,
    );
  }
}

Future<(MaterialReleaseViewmodel, _Repo)> _opened() async {
  final repo = _Repo();
  final vm = MaterialReleaseViewmodel(repository: repo);
  await vm.verify('tok');
  return (vm, repo);
}

void main() {
  test('reads the unit, price and request status', () async {
    final (vm, _) = await _opened();
    expect(vm.verification!.status, 'PARTIAL');
    expect(vm.verification!.items.first.unit, 'BAG');
    expect(vm.verification!.items.first.given, 3);
  });

  test('Give now starts at what can go out', () async {
    final (vm, _) = await _opened();
    expect(vm.giveNow(1), 4);
    expect(vm.giveNow(2), 12.5);
    expect(vm.giveNowChanged(1), isFalse);
  });

  test('Give now is clamped to 0 … releasable', () async {
    final (vm, _) = await _opened();
    vm.setGiveNow(1, 99);
    expect(vm.giveNow(1), 4);
    vm.setGiveNow(1, -3);
    expect(vm.giveNow(1), 0);
  });

  test('a bag is whole; kilos keep 2 decimals', () async {
    final (vm, _) = await _opened();
    vm.setGiveNow(1, 1.5);
    expect(vm.giveNow(1), 1);
    vm.setGiveNow(2, 2.555);
    expect(vm.giveNow(2), 2.55);
    expect(vm.giveNowChanged(2), isTrue);
  });

  test('the summary adds price × Give now and lists what stays open', () async {
    final (vm, _) = await _opened();
    vm.setGiveNow(2, 5);
    expect(vm.todayTotal, 4 * 260 + 5 * 40);
    expect(
      vm.stillOpenAfter.map((l) => (l.name, l.qty, l.unit)).toList(),
      [('Portland Cement — 40kg', 3.0, 'BAG'), ('Tie wire #16', 7.5, 'KG')],
    );
  });

  test('all amounts at 0 blocks the release with a reason', () async {
    final (vm, repo) = await _opened();
    vm.setGiveNow(1, 0);
    vm.setGiveNow(2, 0);
    expect(vm.confirmBlockedReason, 'Set at least one Give now above 0.');
    expect(await vm.release(), isFalse);
    expect(repo.sent, isNull);
  });

  test('release sends the chosen amount for every line that can go', () async {
    final (vm, repo) = await _opened();
    vm.setGiveNow(1, 2);
    expect(await vm.release(), isTrue);
    expect(repo.sent, {1: 2.0, 2: 12.5});
  });

  test('stock moved since opening: reload the request and say so', () async {
    final (vm, repo) = await _opened();
    repo.failRelease = const RequisitionServiceException(
      'Portland Cement (BAG): only 2 can go out now, not 4.',
      code: 'RELEASE_QTY_TOO_HIGH',
    );
    expect(await vm.release(), isFalse);
    expect(repo.verifyCalls, 2);
    expect(
      vm.error,
      'Stock changed since this request was opened. The amounts were updated '
      '— check them and release again.',
    );
  });
}
