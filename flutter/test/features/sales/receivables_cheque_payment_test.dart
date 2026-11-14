// Phase 4 F5: offering a cheque in the utang payment dialog.
//
// The rule this file holds is the one a cashier could otherwise be misled about:
// recording a cheque does NOT pay the debt. The server keeps `balance_due` until
// a manager clears it, so the rows must stay put and the dialog must say "pending
// clearance" instead of any form of "paid".

import 'package:client/data/models/cheque.dart';
import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/data/services/cheque_service.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_receivables_content.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The shared receivables body, which is what the cashier's Record payment shell
/// shows (the shell adds only the POS navigation frame around it).
Widget _app(SalesReceivablesViewmodel viewmodel) =>
    ChangeNotifierProvider.value(
      value: viewmodel..load(),
      child: const MaterialApp(home: Scaffold(body: SalesReceivablesContent())),
    );

class _StubLedgerRepository extends LedgerRepository {
  _StubLedgerRepository() : super();

  int fetchCalls = 0;
  int cashCalls = 0;

  @override
  Future<List<LedgerEntry>> fetchLedgers() async {
    fetchCalls++;
    return [_entry()];
  }

  @override
  Future<void> recordPayment({
    required int collectibleId,
    required double amountPaid,
    dynamic method,
    String? officialReceiptNo,
  }) async {
    cashCalls++;
  }
}

class _StubChequeService extends ChequeService {
  _StubChequeService() : super();

  int calls = 0;
  String? failure;
  int? lastCollectibleId;
  double? lastAmount;
  String? lastNumber;
  String? lastBank;
  DateTime? lastDate;

  @override
  Future<Cheque> recordChequeAgainstLedger({
    required int collectibleId,
    required double amount,
    required String chequeNumber,
    required String bank,
    required DateTime chequeDate,
  }) async {
    calls++;
    lastCollectibleId = collectibleId;
    lastAmount = amount;
    lastNumber = chequeNumber;
    lastBank = bank;
    lastDate = chequeDate;
    final failure = this.failure;
    if (failure != null) throw ChequeServiceException(failure);
    return Cheque(
      id: 7,
      transactionId: 18,
      transactionNo: 'TRX-20261016-0007',
      customerId: 2,
      customerName: 'Dela Cruz Construction',
      ledgerId: collectibleId,
      amount: amount,
      chequeNumber: chequeNumber,
      bank: bank,
      chequeDate: chequeDate,
      status: ChequeStatus.pending,
      referenceNo: '',
      receivedAt: appClock.now(),
    );
  }
}

LedgerEntry _entry() => LedgerEntry(
  id: 4,
  customerId: 2,
  customerName: 'Dela Cruz Construction',
  transactionNo: 'TRX-20261016-0007',
  originalAmount: 5000,
  balanceDue: 472,
  dueDate: appClock.now().add(const Duration(days: 30)),
  isOverdue: false,
);

/// One receivable row, so the dialog has a named customer to offer a cheque to.
Future<SalesReceivablesViewmodel> _pumpCashier(
  WidgetTester tester,
  _StubLedgerRepository repository,
  _StubChequeService cheques,
) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final viewmodel = SalesReceivablesViewmodel(
    repository: repository,
    cheques: cheques,
  );
  await tester.pumpWidget(_app(viewmodel));
  await tester.pumpAndSettle();
  return viewmodel;
}

void main() {
  late _StubLedgerRepository repository;
  late _StubChequeService cheques;

  setUp(() {
    repository = _StubLedgerRepository();
    cheques = _StubChequeService();
  });

  testWidgets('a cheque is recorded without moving the balance', (
    tester,
  ) async {
    final viewmodel = await _pumpCashier(tester, repository, cheques);
    final balanceBefore = viewmodel.entries.single.balanceDue;

    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cheque'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Cheque number'),
      'CHQ-1001',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Bank'), 'BDO');
    await tester.tap(find.text('Date on the cheque'));
    await tester.pumpAndSettle();
    // The picker opens on today's date (the fixed test clock), and OK takes it.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Record cheque'));
    await tester.pumpAndSettle();

    expect(cheques.calls, 1);
    expect(cheques.lastCollectibleId, 4);
    expect(cheques.lastAmount, 472);
    expect(cheques.lastNumber, 'CHQ-1001');
    expect(cheques.lastBank, 'BDO');
    expect(cheques.lastDate, DateTime(2026, 10, 15));

    // No "paid" claim, and the debt is untouched: no reload happened because a
    // pending cheque does not move the server's balance either.
    expect(find.text('Pending clearance'), findsOneWidget);
    expect(find.textContaining('pending clearance'), findsOneWidget);
    expect(find.textContaining('paid'), findsNothing);
    expect(viewmodel.entries.single.balanceDue, balanceBefore);
    expect(repository.fetchCalls, 1, reason: 'no debt moved, so no reload');
    expect(find.text('Close'), findsOneWidget);
  });

  testWidgets('a refused cheque keeps the server sentence on the dialog', (
    tester,
  ) async {
    cheques.failure =
        'A cheque needs a named customer. Walk-in Customer is a walk-in.';
    await _pumpCashier(tester, repository, cheques);

    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cheque'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Cheque number'),
      'CHQ-1001',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Bank'), 'BDO');
    await tester.tap(find.text('Date on the cheque'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Record cheque'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'A cheque needs a named customer. Walk-in Customer is a walk-in.',
      ),
      findsOneWidget,
    );
    expect(find.text('Pending clearance'), findsNothing);
  });

  testWidgets('the cash path still posts a normal payment and closes', (
    tester,
  ) async {
    await _pumpCashier(tester, repository, cheques);

    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record'));
    await tester.pumpAndSettle();

    expect(repository.cashCalls, 1);
    expect(cheques.calls, 0);
    expect(find.text('Record'), findsNothing, reason: 'the dialog closed');
  });

  test(
    'a cheque without its number or bank never reaches the server',
    () async {
      final viewmodel = SalesReceivablesViewmodel(
        repository: repository,
        cheques: cheques,
      );
      await viewmodel.load();

      final cheque = await viewmodel.recordChequePayment(
        entry: _entry(),
        amount: 472,
        chequeNumber: ' ',
        bank: 'BDO',
        chequeDate: appClock.now(),
      );

      expect(cheque, isNull);
      expect(cheques.calls, 0);
      expect(viewmodel.payError, contains('needs its number'));
    },
  );

  test('an over-balance cheque is refused before the server sees it', () async {
    final viewmodel = SalesReceivablesViewmodel(
      repository: repository,
      cheques: cheques,
    );
    await viewmodel.load();

    final cheque = await viewmodel.recordChequePayment(
      entry: _entry(),
      amount: 500,
      chequeNumber: 'CHQ-1001',
      bank: 'BDO',
      chequeDate: appClock.now(),
    );

    expect(cheque, isNull);
    expect(cheques.calls, 0);
    expect(viewmodel.payError, contains('472.00'));
  });
}
