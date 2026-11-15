import 'package:client/core/time/app_clock.dart';
import 'package:client/data/models/cheque.dart';
import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/cheque_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/pos/views/pos_receivables_page.dart';
import 'package:client/features/sales/viewmodels/cheque_queue_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:client/features/sales/views/sales_receivables_page.dart';
import 'package:client/features/sales/widgets/sales_receivables_content.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class _StubLedgerRepository extends LedgerRepository {
  List<LedgerEntry> ledgers = const [];
  List<LedgerPayment> payments = const [];
  List<PaymentReceipt> receipts = const [];

  int approveCalls = 0;
  int declineCalls = 0;
  int? lastApprovedId;
  double? lastApprovedAmount;
  int? lastDeclinedId;
  String? lastDeclinedReason;

  @override
  Future<List<LedgerEntry>> fetchLedgers() async => ledgers;

  @override
  Future<List<LedgerPayment>> fetchPayments({String? search}) async => payments;

  @override
  Future<List<PaymentReceipt>> fetchPaymentReceipts({String? status}) async =>
      receipts;

  @override
  Future<PaymentReceipt> approvePaymentReceipt(
    int id, {
    double? approvedAmount,
  }) async {
    approveCalls++;
    lastApprovedId = id;
    lastApprovedAmount = approvedAmount;
    final target = receipts.firstWhere((r) => r.id == id);
    final updated = PaymentReceipt(
      id: target.id,
      cpmsPaymentId: target.cpmsPaymentId,
      cpmsProjectId: target.cpmsProjectId,
      projectName: target.projectName,
      customerName: target.customerName,
      amount: target.amount,
      approvedAmount: approvedAmount ?? target.amount,
      paymentMethod: target.paymentMethod,
      referenceNo: target.referenceNo,
      notes: target.notes,
      submittedByName: target.submittedByName,
      status: 'APPROVED',
      declineReason: '',
      createdAt: target.createdAt,
      decidedByName: 'Store Manager',
      decidedAt: DateTime(2026, 11, 16, 10, 0),
    );
    receipts = [
      for (final r in receipts) r.id == id ? updated : r,
    ];
    return updated;
  }

  @override
  Future<PaymentReceipt> declinePaymentReceipt(
    int id, {
    required String reason,
  }) async {
    declineCalls++;
    lastDeclinedId = id;
    lastDeclinedReason = reason;
    final target = receipts.firstWhere((r) => r.id == id);
    final updated = PaymentReceipt(
      id: target.id,
      cpmsPaymentId: target.cpmsPaymentId,
      cpmsProjectId: target.cpmsProjectId,
      projectName: target.projectName,
      customerName: target.customerName,
      amount: target.amount,
      paymentMethod: target.paymentMethod,
      referenceNo: target.referenceNo,
      notes: target.notes,
      submittedByName: target.submittedByName,
      status: 'DECLINED',
      declineReason: reason,
      createdAt: target.createdAt,
      decidedByName: 'Store Manager',
      decidedAt: DateTime(2026, 11, 16, 11, 0),
    );
    receipts = [
      for (final r in receipts) r.id == id ? updated : r,
    ];
    return updated;
  }
}

class _StubChequeService extends ChequeService {
  @override
  Future<List<Cheque>> fetchCheques() async => const [];
}

Future<SalesReceivablesViewmodel> _pump(
  WidgetTester tester, {
  required _StubLedgerRepository repository,
  required bool manager,
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final cheques = _StubChequeService();
  final vm = SalesReceivablesViewmodel(
    repository: repository,
    cheques: cheques,
  );
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: vm..load()),
        if (manager)
          ChangeNotifierProvider.value(
            value: ChequeQueueViewmodel(service: cheques)..load(),
          ),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: SalesReceivablesContent(showCheques: manager),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  return vm;
}

List<LedgerEntry> _sampleLedgers() => [
  LedgerEntry(
    id: 1,
    customerId: 10,
    customerName: 'Reyes Construction',
    projectName: 'Tower A',
    transactionNo: 'TXN-OPEN-001',
    originalAmount: 1500,
    balanceDue: 900,
    dueDate: appClock.now().add(const Duration(days: 20)),
    isOverdue: false,
  ),
  LedgerEntry(
    id: 2,
    customerId: 11,
    customerName: 'Santos Builders',
    projectName: 'Warehouse B',
    transactionNo: 'TXN-PAID-002',
    originalAmount: 1000,
    balanceDue: 0,
    dueDate: appClock.now().subtract(const Duration(days: 5)),
    isOverdue: false,
    paidAt: DateTime(2026, 11, 15, 14, 30),
  ),
];

List<LedgerPayment> _samplePayments() => [
  LedgerPayment(
    id: 2,
    collectibleId: 2,
    customerName: 'Santos Builders',
    projectName: 'Warehouse B',
    transactionNo: 'TXN-PAID-002',
    amountPaid: 1000,
    paymentMethod: 'BANK_TRANSFER',
    paymentDate: DateTime(2026, 11, 15, 14, 30),
    officialReceiptNo: 'BDO-998877',
    processedByName: 'Store Manager',
    paymentReceiptId: 7,
    cpmsReceiptRef: 'BDO-998877',
  ),
  LedgerPayment(
    id: 1,
    collectibleId: 1,
    customerName: 'Counter Customer',
    transactionNo: 'TXN-WALKIN-001',
    amountPaid: 600,
    paymentMethod: 'CASH',
    paymentDate: DateTime(2026, 11, 14, 9, 15),
    officialReceiptNo: 'OR-4411',
    processedByName: 'Maria Cashier',
  ),
];

List<PaymentReceipt> _sampleReceipts() => [
  PaymentReceipt(
    id: 7,
    cpmsPaymentId: 'PAY-0007',
    cpmsProjectId: 'PRJ-101',
    projectName: 'Tower A',
    customerName: 'Reyes Construction',
    amount: 1200,
    paymentMethod: 'BANK_TRANSFER',
    referenceNo: 'BDO-998877',
    notes: 'Online transfer',
    submittedByName: 'Liza',
    status: 'WAITING',
    declineReason: '',
    createdAt: DateTime(2026, 11, 16, 8, 0),
  ),
  PaymentReceipt(
    id: 6,
    cpmsPaymentId: 'PAY-0006',
    cpmsProjectId: 'PRJ-102',
    projectName: 'Warehouse B',
    customerName: 'Santos Builders',
    amount: 1000,
    approvedAmount: 1000,
    paymentMethod: 'GCASH',
    referenceNo: 'GC-554433',
    notes: '',
    submittedByName: 'Liza',
    status: 'APPROVED',
    declineReason: '',
    createdAt: DateTime(2026, 11, 15, 13, 0),
    decidedByName: 'Store Manager',
    decidedAt: DateTime(2026, 11, 15, 14, 30),
  ),
  PaymentReceipt(
    id: 5,
    cpmsPaymentId: 'PAY-0005',
    cpmsProjectId: 'PRJ-103',
    projectName: 'Annex C',
    customerName: 'Cruz Contractors',
    amount: 500,
    paymentMethod: 'GCASH',
    referenceNo: 'GC-000111',
    notes: '',
    submittedByName: 'Liza',
    status: 'DECLINED',
    declineReason: 'Reference not found in statement',
    createdAt: DateTime(2026, 11, 14, 11, 0),
    decidedByName: 'Store Manager',
    decidedAt: DateTime(2026, 11, 14, 15, 0),
  ),
];

void main() {
  testWidgets(
    'payment history segment is visible to cashier (read-only), supports search and paging',
    (tester) async {
      final repo = _StubLedgerRepository()
        ..ledgers = _sampleLedgers()
        ..payments = [
          for (var i = 27; i >= 1; i--)
            LedgerPayment(
              id: i,
              collectibleId: i,
              customerName: i == 27 ? 'Santos Builders' : 'Customer $i',
              projectName: i == 27 ? 'Warehouse B' : null,
              transactionNo: 'TXN-${i.toString().padLeft(4, '0')}',
              amountPaid: 100.0 + i,
              paymentMethod: i == 27 ? 'BANK_TRANSFER' : 'CASH',
              paymentDate: DateTime(2026, 11, 1, 9, 0).add(Duration(hours: i)),
              officialReceiptNo: i == 27 ? 'BDO-998877' : 'OR-$i',
              processedByName: i == 27 ? 'Store Manager' : 'Maria Cashier',
              paymentReceiptId: i == 27 ? 7 : null,
              cpmsReceiptRef: i == 27 ? 'BDO-998877' : null,
            ),
        ]
        ..receipts = _sampleReceipts();

      await _pump(tester, repository: repo, manager: false);

      // Cashier sees Receivables + Payment history, never CPMS receipts or Cheques.
      expect(find.text('Receivables'), findsOneWidget);
      expect(find.text('Payment history'), findsOneWidget);
      expect(find.text('CPMS receipts'), findsNothing);
      expect(find.textContaining('Review CPMS payment receipts'), findsNothing);

      await tester.tap(find.text('Payment history'));
      await tester.pumpAndSettle();

      // Paging shows page 1 (25 rows of 27) and newest row first with CPMS receipt note.
      expect(find.text('1 to 25 of 27'), findsOneWidget);
      expect(find.text('Santos Builders'), findsOneWidget);
      expect(find.text('Warehouse B'), findsOneWidget);
      expect(find.text('TXN-0027'), findsOneWidget);
      expect(find.text('Bank transfer'), findsOneWidget);
      expect(find.text('CPMS receipt BDO-998877'), findsOneWidget);
      expect(find.text('Store Manager'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Decline'), findsNothing);

      // Next page shows rows 26 to 27.
      await tester.tap(find.byKey(const ValueKey('DataPanel.next')));
      await tester.pumpAndSettle();
      expect(find.text('26 to 27 of 27'), findsOneWidget);
      expect(find.text('Customer 1'), findsOneWidget);

      // Search matches reference number, project, or customer.
      await tester.enterText(find.byType(TextField), 'BDO-998877');
      await tester.pumpAndSettle();
      expect(find.text('Santos Builders'), findsOneWidget);
      expect(find.text('Customer 26'), findsNothing);
    },
  );

  testWidgets(
    'manager CPMS receipts log lists all statuses, filters by status, and reuses approve/decline dialogs',
    (tester) async {
      final repo = _StubLedgerRepository()
        ..ledgers = _sampleLedgers()
        ..payments = _samplePayments()
        ..receipts = _sampleReceipts();

      await _pump(tester, repository: repo, manager: true);

      // Shortcut remains visible on Utang tab while WAITING receipts exist.
      expect(find.text('Review CPMS payment receipts (1)'), findsOneWidget);

      await tester.tap(find.text('CPMS receipts'));
      await tester.pumpAndSettle();

      // Shows Waiting, Approved, and Declined receipts together.
      expect(find.text('Tower A'), findsOneWidget);
      expect(find.text('Warehouse B'), findsOneWidget);
      expect(find.text('Annex C'), findsOneWidget);
      expect(find.text('Approved ₱1,000.00'), findsOneWidget);
      expect(find.text('Reference not found in statement'), findsOneWidget);

      // Filter chips narrow by status.
      await tester.tap(
        find.descendant(
          of: find.byType(FilterBar),
          matching: find.text('Declined'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Annex C'), findsOneWidget);
      expect(find.text('Tower A'), findsNothing);

      await tester.tap(
        find.descendant(
          of: find.byType(FilterBar),
          matching: find.text('Waiting'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Tower A'), findsOneWidget);
      expect(find.text('Annex C'), findsNothing);

      // Approving from the CPMS receipts log opens the shared approval dialog.
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(find.text('Approve receipt · BDO-998877'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        '900.00',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();

      expect(repo.approveCalls, 1);
      expect(repo.lastApprovedId, 7);
      expect(repo.lastApprovedAmount, 900);
    },
  );

  testWidgets(
    'manager can decline a waiting receipt from CPMS receipts log',
    (tester) async {
      final repo = _StubLedgerRepository()
        ..ledgers = _sampleLedgers()
        ..receipts = _sampleReceipts();

      await _pump(tester, repository: repo, manager: true);
      await tester.tap(find.text('CPMS receipts'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      expect(find.text('Decline receipt · BDO-998877'), findsOneWidget);
      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(TextField),
        ),
        'Duplicate receipt',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Decline'));
      await tester.pumpAndSettle();

      expect(repo.declineCalls, 1);
      expect(repo.lastDeclinedId, 7);
      expect(repo.lastDeclinedReason, 'Duplicate receipt');
    },
  );

  testWidgets(
    'Review CPMS payment receipts shortcut dialog reuses the shared approval flow',
    (tester) async {
      final repo = _StubLedgerRepository()
        ..ledgers = _sampleLedgers()
        ..receipts = _sampleReceipts();

      await _pump(tester, repository: repo, manager: true);
      await tester.tap(find.text('Review CPMS payment receipts (1)'));
      await tester.pumpAndSettle();

      expect(find.text('CPMS payment receipts'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(find.text('Approve receipt · BDO-998877'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
      await tester.pumpAndSettle();

      expect(repo.approveCalls, 1);
      expect(repo.lastApprovedId, 7);
      expect(find.text('No waiting CPMS payment receipts.'), findsOneWidget);
    },
  );

  testWidgets(
    'Paid filter chip shows settled ledgers with paid date and preserves open totals',
    (tester) async {
      final repo = _StubLedgerRepository()..ledgers = _sampleLedgers();
      final vm = await _pump(tester, repository: repo, manager: true);

      // Open balance totals ignore the settled row (₱900.00 outstanding, 1 open invoice).
      expect(vm.outstanding, 900);
      expect(find.text('1 open invoices'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(FilterBar),
          matching: find.text('Paid'),
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: find.byType(FilterBar),
          matching: find.text('Paid'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Santos Builders'), findsOneWidget);
      expect(find.text('Reyes Construction'), findsNothing);
      expect(find.text('Paid Nov 15, 2026'), findsOneWidget);
      expect(find.text('Record payment'), findsNothing);
    },
  );

  for (final width in const [1440.0, 1100.0, 760.0]) {
    testWidgets(
      'full manager page tabs render without overflow at ${width.toInt()} px wide',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repo = _StubLedgerRepository()
          ..ledgers = _sampleLedgers()
          ..payments = _samplePayments()
          ..receipts = _sampleReceipts();

        await tester.pumpWidget(
          ChangeNotifierProvider<AuthViewmodel>.value(
            value: AuthViewmodel(AuthRepository(AuthService())),
            child: MaterialApp(
              home: SalesReceivablesPage(
                viewmodel: SalesReceivablesViewmodel(repository: repo),
                chequeViewmodel: ChequeQueueViewmodel(
                  service: _StubChequeService(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Payment history'));
        await tester.pumpAndSettle();
        expect(find.byType(DataPanel<LedgerPayment>), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('CPMS receipts'));
        await tester.pumpAndSettle();
        expect(find.byType(DataPanel<PaymentReceipt>), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'full cashier page payment history renders without overflow at ${width.toInt()} px wide',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final repo = _StubLedgerRepository()
          ..ledgers = _sampleLedgers()
          ..payments = _samplePayments()
          ..receipts = _sampleReceipts();

        await tester.pumpWidget(
          ChangeNotifierProvider<AuthViewmodel>.value(
            value: AuthViewmodel(AuthRepository(AuthService())),
            child: MaterialApp(
              home: PosReceivablesPage(
                viewmodel: SalesReceivablesViewmodel(repository: repo),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(find.text('Payment history'));
        await tester.pumpAndSettle();
        expect(find.byType(DataPanel<LedgerPayment>), findsOneWidget);
        expect(find.text('CPMS receipt BDO-998877'), findsOneWidget);
        expect(find.text('Approve'), findsNothing);
        expect(find.text('Decline'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
