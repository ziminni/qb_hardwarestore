// Phase 4 F5: the manager's cheque queue viewmodel.
//
// The rules held here are the ones a wrong answer costs money for:
//  * pending first, then oldest FIRST - the queue exists to chase the cheque at
//    risk, so a newest-first list buries it;
//  * a decision refreshes from the server instead of editing the row locally, and
//    a 409 conflict refreshes too, so the table can never show a PENDING row the
//    server has already settled;
//  * a failed load keeps the rows it had - emptying the table would say "no
//    cheques to chase", which a failed read has not established;
//  * one decision per cheque in flight, because clearing twice is a debt paid
//    that nobody paid.

import 'dart:async';

import 'package:client/data/models/cheque.dart';
import 'package:client/data/services/cheque_service.dart';
import 'package:client/features/sales/viewmodels/cheque_queue_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubChequeService extends ChequeService {
  _StubChequeService() : super();

  List<Cheque> rows = const [];
  String? loadFailure;
  String? decideFailure;
  String? decideCode;
  int fetchCalls = 0;
  int clearCalls = 0;
  int bounceCalls = 0;
  String? lastReason;

  /// Gates a decision in flight, so the duplicate-submission guard is observable.
  Completer<void>? holdDecide;

  @override
  Future<List<Cheque>> fetchCheques() async {
    fetchCalls++;
    final failure = loadFailure;
    if (failure != null) throw ChequeServiceException(failure);
    return rows;
  }

  @override
  Future<Cheque> clear(int id) async {
    clearCalls++;
    final gate = holdDecide;
    if (gate != null) await gate.future;
    final failure = decideFailure;
    if (failure != null) {
      throw ChequeServiceException(failure, code: decideCode);
    }
    return _cheque(id: id, status: ChequeStatus.cleared);
  }

  @override
  Future<Cheque> bounce(int id, String reason) async {
    bounceCalls++;
    lastReason = reason;
    final gate = holdDecide;
    if (gate != null) await gate.future;
    final failure = decideFailure;
    if (failure != null) {
      throw ChequeServiceException(failure, code: decideCode);
    }
    return _cheque(id: id, status: ChequeStatus.bounced);
  }
}

Cheque _cheque({
  int id = 1,
  int ledgerId = 4,
  String chequeDate = '2026-11-20',
  ChequeStatus status = ChequeStatus.pending,
  String customerName = 'Dela Cruz Construction',
  double amount = 15,
}) => Cheque(
  id: id,
  transactionId: 18,
  transactionNo: 'TRX-20261016-0007',
  customerId: 2,
  customerName: customerName,
  ledgerId: ledgerId,
  amount: amount,
  chequeNumber: 'CHQ-100$id',
  bank: 'BDO',
  chequeDate: DateTime.parse(chequeDate),
  status: status,
  referenceNo: '',
  receivedAt: DateTime(2026, 10, 16, 18, 56),
);

void main() {
  late _StubChequeService service;
  late ChequeQueueViewmodel viewmodel;

  setUp(() {
    service = _StubChequeService();
    viewmodel = ChequeQueueViewmodel(service: service);
  });

  test('starts empty, not loading, nothing pending', () {
    expect(viewmodel.cheques, isEmpty);
    expect(viewmodel.isLoading, isFalse);
    expect(viewmodel.loadError, isNull);
    expect(viewmodel.pendingCount, 0);
  });

  test('pending cheques come first, oldest cheque date first', () async {
    service.rows = [
      _cheque(id: 1, chequeDate: '2026-11-01', status: ChequeStatus.cleared),
      _cheque(id: 2, chequeDate: '2026-12-05'),
      _cheque(id: 3, chequeDate: '2026-11-10'),
      _cheque(id: 4, chequeDate: '2026-10-20', status: ChequeStatus.bounced),
    ];

    await viewmodel.load();

    // Pending first (oldest first), then the decided rows, also oldest first.
    expect(viewmodel.cheques.map((cheque) => cheque.id).toList(), [3, 2, 4, 1]);
    expect(viewmodel.pendingCount, 2);
  });

  test('the status filter narrows without hiding the pending count', () async {
    service.rows = [
      _cheque(id: 1),
      _cheque(id: 2),
      _cheque(id: 3, status: ChequeStatus.cleared),
    ];
    await viewmodel.load();

    viewmodel.setStatusFilter(ChequeStatus.cleared);

    expect(viewmodel.filteredCheques.map((cheque) => cheque.id).toList(), [3]);
    expect(viewmodel.pendingCount, 2);
  });

  test('a failed load keeps the rows it already had', () async {
    service.rows = [_cheque(id: 1)];
    await viewmodel.load();

    service.loadFailure = 'Cannot connect to the BuildPro server.';
    await viewmodel.load();

    expect(viewmodel.loadError, 'Cannot connect to the BuildPro server.');
    expect(viewmodel.cheques, hasLength(1));
  });

  test('clearing reloads the queue from the server', () async {
    service.rows = [_cheque(id: 1)];
    await viewmodel.load();
    // The server now reports it cleared; the viewmodel must not invent the row.
    service.rows = [_cheque(id: 1, status: ChequeStatus.cleared)];

    final ok = await viewmodel.clear(viewmodel.cheques.first);

    expect(ok, isTrue);
    expect(service.clearCalls, 1);
    expect(
      service.fetchCalls,
      2,
      reason: 'the queue is re-read after a decision',
    );
    expect(viewmodel.pendingCount, 0);
    expect(viewmodel.cheques.single.status, ChequeStatus.cleared);
  });

  test('a 409 conflict refreshes and keeps the server sentence', () async {
    service.rows = [_cheque(id: 1)];
    await viewmodel.load();
    service.rows = [_cheque(id: 1, status: ChequeStatus.bounced)];
    service.decideFailure =
        'CHQ-1001 is already bounced and cannot be decided again.';
    service.decideCode = 'CHEQUE_ALREADY_DECIDED';

    final ok = await viewmodel.clear(viewmodel.cheques.first);

    expect(ok, isFalse);
    expect(
      viewmodel.decisionError,
      'CHQ-1001 is already bounced and cannot be decided again.',
    );
    expect(service.fetchCalls, 2, reason: 'a conflict must re-read the rows');
    expect(viewmodel.cheques.single.status, ChequeStatus.bounced);
  });

  test('a bounce with no reason never reaches the server', () async {
    service.rows = [_cheque(id: 1)];
    await viewmodel.load();

    final ok = await viewmodel.bounce(viewmodel.cheques.first, '   ');

    expect(ok, isFalse);
    expect(service.bounceCalls, 0);
    expect(viewmodel.decisionError, contains('needs a reason'));
  });

  test(
    'a second clear on the same cheque is refused while one is in flight',
    () async {
      service.rows = [_cheque(id: 1)];
      await viewmodel.load();
      final cheque = viewmodel.cheques.first;
      service.holdDecide = Completer<void>();

      final first = viewmodel.clear(cheque);
      final second = await viewmodel.clear(cheque);
      service.holdDecide!.complete();
      final firstResult = await first;

      expect(second, isFalse);
      expect(firstResult, isTrue);
      expect(
        service.clearCalls,
        1,
        reason: 'one decision per cheque at a time',
      );
      expect(viewmodel.isDeciding(cheque.id), isFalse);
    },
  );

  test(
    'a decision recorded but an unreadable refresh says so honestly',
    () async {
      service.rows = [_cheque(id: 1)];
      await viewmodel.load();
      final cheque = viewmodel.cheques.first;
      // The decision lands, then the follow-up read fails.
      service.decideFailure = 'Cannot connect to the BuildPro server.';
      service.decideCode = null;

      final ok = await viewmodel.clear(cheque);

      expect(ok, isFalse);
      expect(viewmodel.decisionError, 'Cannot connect to the BuildPro server.');
      expect(viewmodel.cheques, hasLength(1), reason: 'rows stay truthful');
    },
  );

  test('a decided cheque cannot be decided again from the screen', () async {
    service.rows = [_cheque(id: 1, status: ChequeStatus.bounced)];
    await viewmodel.load();

    final ok = await viewmodel.clear(viewmodel.cheques.first);

    expect(ok, isFalse);
    expect(service.clearCalls, 0);
    expect(viewmodel.decisionError, contains('already'));
  });
}
