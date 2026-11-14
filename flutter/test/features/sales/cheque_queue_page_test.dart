// Phase 4 F5: the manager's Cheques tab, end to end through the real page.
//
// Held here:
//  * the tab exists on the Store Manager's Receivables screen and carries the
//    pending count, which is the whole global marker decision 18 asks for;
//  * a cashier's Record payment shell has NO Cheques tab - a cashier takes a
//    cheque, a manager decides it;
//  * Clear asks first, Bounce refuses an empty reason, and a 409 keeps the
//    server's sentence over rows that were re-read.

import 'package:client/data/models/cheque.dart';
import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/data/services/cheque_service.dart';
import 'package:client/features/sales/viewmodels/cheque_queue_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_receivables_content.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The receivables BODY, which is the whole screen for both roles. The role
/// shells add only their navigation frame, so pumping the body here is what the
/// manager and the cashier actually see of this screen.
Widget _app(
  SalesReceivablesViewmodel receivables, {
  ChequeQueueViewmodel? cheques,
}) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: receivables..load()),
    if (cheques != null) ChangeNotifierProvider.value(value: cheques..load()),
  ],
  child: MaterialApp(
    home: Scaffold(body: SalesReceivablesContent(showCheques: cheques != null)),
  ),
);

class _StubLedgerRepository extends LedgerRepository {
  _StubLedgerRepository() : super();

  @override
  Future<List<LedgerEntry>> fetchLedgers() async => [
    LedgerEntry(
      id: 4,
      customerId: 2,
      customerName: 'Dela Cruz Construction',
      transactionNo: 'TRX-20261016-0007',
      originalAmount: 5000,
      balanceDue: 472,
      dueDate: appClock.now().add(const Duration(days: 30)),
      isOverdue: false,
    ),
  ];

  @override
  Future<void> recordPayment({
    required int collectibleId,
    required double amountPaid,
    dynamic method,
    String? officialReceiptNo,
  }) async {}
}

class _StubChequeService extends ChequeService {
  _StubChequeService() : super();

  List<Cheque> rows = const [];
  String? loadFailure;
  String? decideFailure;
  String? decideCode;
  int fetchChequesCalls = 0;
  int clearCalls = 0;
  int bounceCalls = 0;
  String? lastReason;

  @override
  Future<List<Cheque>> fetchCheques() async {
    fetchChequesCalls++;
    final failure = loadFailure;
    if (failure != null) throw ChequeServiceException(failure);
    return rows;
  }

  @override
  Future<Cheque> clear(int chequeId) async {
    clearCalls++;
    final failure = decideFailure;
    if (failure != null) {
      throw ChequeServiceException(failure, code: decideCode);
    }
    return _cheque(id: chequeId, status: ChequeStatus.cleared);
  }

  @override
  Future<Cheque> bounce(int chequeId, String reason) async {
    bounceCalls++;
    lastReason = reason;
    final failure = decideFailure;
    if (failure != null) {
      throw ChequeServiceException(failure, code: decideCode);
    }
    return _cheque(id: chequeId, status: ChequeStatus.bounced);
  }
}

Cheque _cheque({
  int id = 7,
  ChequeStatus status = ChequeStatus.pending,
  double amount = 15,
  String? decisionReason,
}) => Cheque(
  id: id,
  transactionId: 18,
  transactionNo: 'TRX-20261016-0007',
  customerId: 2,
  customerName: 'Dela Cruz Construction',
  ledgerId: 4,
  amount: amount,
  chequeNumber: 'CHQ-1001',
  bank: 'BDO',
  chequeDate: DateTime(2026, 11, 20),
  status: status,
  referenceNo: '',
  receivedAt: DateTime(2026, 10, 16, 18, 56),
  decisionReason: decisionReason,
);

void _sizeUp(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

late _StubChequeService _service;

Future<ChequeQueueViewmodel> _pumpManager(WidgetTester tester) async {
  _sizeUp(tester);
  final cheques = ChequeQueueViewmodel(service: _service);
  await tester.pumpWidget(
    _app(
      SalesReceivablesViewmodel(
        repository: _StubLedgerRepository(),
        cheques: _service,
      ),
      cheques: cheques,
    ),
  );
  await tester.pumpAndSettle();
  return cheques;
}

void main() {
  setUp(() {
    _service = _StubChequeService();
  });

  testWidgets('the manager sees a Cheques tab carrying the pending count', (
    tester,
  ) async {
    _service.rows = [
      _cheque(id: 7),
      _cheque(id: 8),
      _cheque(id: 9, status: ChequeStatus.cleared),
    ];

    await _pumpManager(tester);

    expect(find.text('Cheques (2)'), findsOneWidget);
    expect(find.text('Utang'), findsOneWidget);
  });

  testWidgets('the queue lists pending first and offers Clear and Bounce', (
    tester,
  ) async {
    _service.rows = [
      _cheque(id: 9, status: ChequeStatus.cleared),
      _cheque(id: 7),
    ];
    await _pumpManager(tester);

    await tester.tap(find.text('Cheques (1)'));
    await tester.pumpAndSettle();

    expect(find.text('Dela Cruz Construction'), findsWidgets);
    expect(find.text('CHQ-1001 · BDO'), findsNWidgets(2));
    expect(find.text('Clear'), findsOneWidget);
    expect(find.text('Bounce'), findsOneWidget);
  });

  testWidgets('clearing asks first, then re-reads the queue', (tester) async {
    _service.rows = [_cheque(id: 7)];
    await _pumpManager(tester);
    await tester.tap(find.text('Cheques (1)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();

    // The confirmation names what is about to happen.
    expect(find.text('Clear cheque CHQ-1001'), findsOneWidget);
    expect(find.text('This records money received'), findsOneWidget);
    expect(_service.clearCalls, 0, reason: 'nothing posts before confirming');

    // The server now reports it cleared.
    _service.rows = [_cheque(id: 7, status: ChequeStatus.cleared)];
    await tester.tap(find.widgetWithText(FilledButton, 'Clear cheque'));
    await tester.pumpAndSettle();

    expect(_service.clearCalls, 1);
    expect(find.text('Clear cheque CHQ-1001'), findsNothing);
    // One badge on the row; the chip that filters by the same status carries
    // the same word, so the count is "at least one".
    expect(find.text('Cleared'), findsWidgets);
    expect(find.text('Cheques (0)'), findsOneWidget);
  });

  testWidgets('a bounce cannot be sent without a reason', (tester) async {
    _service.rows = [_cheque(id: 7)];
    await _pumpManager(tester);
    await tester.tap(find.text('Cheques (1)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Bounce'));
    await tester.pumpAndSettle();

    final confirm = find.widgetWithText(FilledButton, 'Mark bounced');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    expect(_service.bounceCalls, 0);

    _service.rows = [
      _cheque(
        id: 7,
        status: ChequeStatus.bounced,
        decisionReason: 'Insufficient funds',
      ),
    ];
    await tester.enterText(
      find.widgetWithText(TextField, 'Why did the bank refuse it?'),
      'Insufficient funds',
    );
    await tester.pumpAndSettle();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(_service.bounceCalls, 1);
    expect(_service.lastReason, 'Insufficient funds');
    expect(find.text('Bounced'), findsWidgets);
    expect(find.text('Insufficient funds'), findsWidgets);
  });

  testWidgets('a 409 keeps the server sentence and the refreshed row', (
    tester,
  ) async {
    _service.rows = [_cheque(id: 7)];
    await _pumpManager(tester);
    await tester.tap(find.text('Cheques (1)'));
    await tester.pumpAndSettle();

    // Someone else decided it: the server now reports BOUNCED, and refuses.
    _service.rows = [_cheque(id: 7, status: ChequeStatus.bounced)];
    _service.decideFailure =
        'CHQ-1001 is already bounced and cannot be decided again.';
    _service.decideCode = 'CHEQUE_ALREADY_DECIDED';

    await tester.tap(find.text('Clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear cheque'));
    await tester.pumpAndSettle();

    // Said twice on purpose: on the dialog the manager is reading, and on the
    // queue banner that outlives it.
    expect(
      find.text('CHQ-1001 is already bounced and cannot be decided again.'),
      findsWidgets,
    );
    // The stale PENDING row is gone from under the dialog.
    expect(find.text('Bounced'), findsWidgets);
  });

  testWidgets('a failed queue load is one banner, never a faked zero', (
    tester,
  ) async {
    _service.loadFailure = 'You do not have access to cheques.';
    await _pumpManager(tester);

    await tester.tap(find.text('Cheques (0)'));
    await tester.pumpAndSettle();

    expect(find.byType(ErrorBanner), findsWidgets);
    expect(find.text('You do not have access to cheques.'), findsOneWidget);
    expect(find.text('No cheques on file yet.'), findsNothing);
  });

  testWidgets('without the manager flag there is no Cheques tab at all', (
    tester,
  ) async {
    // This is the cashier's Record payment shell: same body, no cheque
    // viewmodel provided, and therefore no way to reach the decision queue.
    _sizeUp(tester);
    await tester.pumpWidget(
      _app(
        SalesReceivablesViewmodel(
          repository: _StubLedgerRepository(),
          cheques: _service,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Utang'), findsNothing);
    expect(find.textContaining('Cheques ('), findsNothing);
    expect(find.text('Record payment'), findsOneWidget);
    expect(_service.fetchChequesCalls, 0);
  });
}
