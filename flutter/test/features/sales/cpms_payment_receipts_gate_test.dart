// Phase 1c: approving a CPMS payment receipt moves project debt, so it is a
// manager decision like clearing a cheque. The server refuses cashiers (403);
// the cashier's Record payment shell must not offer the button either.

import 'package:client/data/models/cheque.dart';
import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/data/services/cheque_service.dart';
import 'package:client/features/sales/viewmodels/cheque_queue_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_receivables_content.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubLedgerRepository extends LedgerRepository {
  @override
  Future<List<LedgerEntry>> fetchLedgers() async => const [];

  @override
  Future<List<PaymentReceipt>> fetchPaymentReceipts({String? status}) async => [
    PaymentReceipt(
      id: 1,
      cpmsPaymentId: 'PAY-0001',
      cpmsProjectId: 'PRJ-101',
      projectName: 'Tower A',
      customerName: 'Dela Cruz Construction',
      amount: 600,
      paymentMethod: 'BANK_TRANSFER',
      referenceNo: 'BDO-1',
      notes: '',
      submittedByName: 'Liza',
      status: 'WAITING',
      declineReason: '',
      createdAt: DateTime(2026, 11, 16),
    ),
  ];
}

class _StubChequeService extends ChequeService {
  @override
  Future<List<Cheque>> fetchCheques() async => const [];
}

Future<void> _pump(WidgetTester tester, {required bool manager}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final cheques = _StubChequeService();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(
          value: SalesReceivablesViewmodel(
            repository: _StubLedgerRepository(),
            cheques: cheques,
          )..load(),
        ),
        if (manager)
          ChangeNotifierProvider.value(
            value: ChequeQueueViewmodel(service: cheques)..load(),
          ),
      ],
      child: MaterialApp(
        home: Scaffold(body: SalesReceivablesContent(showCheques: manager)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the manager is offered the CPMS receipt review', (tester) async {
    await _pump(tester, manager: true);
    expect(find.text('Review CPMS payment receipts (1)'), findsOneWidget);
  });

  testWidgets('the cashier is not offered the CPMS receipt review', (
    tester,
  ) async {
    await _pump(tester, manager: false);
    expect(find.textContaining('Review CPMS payment receipts'), findsNothing);
  });
}
