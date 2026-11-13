// Phase 5 F2 (decision 18): the supplier payables screen.
//
// Pinned here, in the three role shells the routes mount:
//   * Stock Manager (inventory shell) reads the page and gets NO Pay control —
//     the server refuses the POST for that role, so a button could only fail;
//   * Store Manager (sales shell) and Admin (admin shell) do get it;
//   * the summary says what the shop owes per supplier, and the bills table
//     opens one bill's payment history;
//   * at 760 px with 1.3x text and the real fonts nothing clips.

import 'dart:io';

import 'package:client/core/format/format.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/supplier_payables.dart';
import 'package:client/data/models/supplier_returns.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/payables_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/payables_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/payables/viewmodels/payables_viewmodel.dart';
import 'package:client/features/payables/views/payables_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

SupplierBill _bill({
  int id = 4,
  double balance = 400,
  bool overdue = true,
  SupplierBillStatus status = SupplierBillStatus.partial,
  List<SupplierPayment> payments = const [],
}) => SupplierBill(
  id: id,
  receiptId: id + 5,
  purchaseOrderId: 41,
  supplierId: 2,
  supplierName: 'Cebu Steel Works',
  receivedDate: DateTime(2026, 10, 1),
  termsDays: 30,
  dueDate: DateTime(2026, 10, 31),
  grossAmount: 1000,
  discountAmount: 100,
  netAmount: 900,
  vatableAmount: 803.57,
  vatAmount: 96.43,
  vatRate: 12,
  totalAmount: 900,
  balanceAmount: balance,
  paidAmount: 900 - balance,
  status: status,
  isOverdue: overdue,
  payments: payments,
);

class _StubRepository extends PayablesRepository {
  _StubRepository({List<SupplierBill>? bills, this.summary = const []})
    : bills = bills ?? [_bill()];

  List<SupplierBill> bills;
  final List<SupplierPayable> summary;
  final List<Map<String, dynamic>> posted = [];
  String? failure;

  List<SupplierCreditNote> creditNotes = const [];
  List<SupplierPayment> chequeRows = const [];

  @override
  Future<List<SupplierBill>> fetchBills({
    int? supplierId,
    SupplierBillStatus? status,
    bool overdueOnly = false,
  }) async {
    if (failure != null) throw PayablesServiceException(failure!);
    return bills;
  }

  @override
  Future<List<SupplierPayable>> fetchSummary() async => summary;

  @override
  Future<SupplierBill> fetchBill(int id) async =>
      bills.firstWhere((bill) => bill.id == id);

  @override
  Future<void> createPayment(Map<String, dynamic> body) async {
    posted.add(body);
  }

  @override
  Future<List<SupplierCreditNote>> fetchCreditNotes({
    int? supplierId,
    bool openOnly = false,
  }) async => creditNotes;

  @override
  Future<List<SupplierPayment>> fetchCheques({
    int? supplierId,
    SupplierPaymentStatus? status,
  }) async => chequeRows;
}

SupplierCreditNote _note({
  int id = 12,
  String number = 'CN-20261113-0001',
  double total = 300,
  double remaining = 200,
}) => SupplierCreditNote(
  id: id,
  number: number,
  supplierId: 2,
  supplierName: 'Cebu Steel Works',
  supplierReturnId: 3,
  sourceBillId: 4,
  value: 267.86,
  vatRate: 12,
  vatInclusive: true,
  vatAmount: 32.14,
  totalAmount: total,
  remainingAmount: remaining,
  appliedAmount: total - remaining,
  createdAt: DateTime(2026, 11, 13),
);

const _summaryRow = SupplierPayable(
  supplierId: 2,
  supplierName: 'Cebu Steel Works',
  billCount: 3,
  original: 3000,
  paid: 1000,
  balance: 2000,
  overdue: 500,
);

Future<void> _loadAppFonts() async {
  for (final (family, files) in [
    ('OpenSans', ['OpenSans-Regular.ttf', 'OpenSans-Bold.ttf']),
    ('Cinzel', ['Cinzel-Regular.ttf', 'Cinzel-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
}

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  Size size = const Size(1400, 1000),
  double scale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewmodel>(
          create: (_) => AuthViewmodel(AuthRepository(AuthService())),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: page,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _payButton() => find.byTooltip('Record a payment');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(_loadAppFonts);

  testWidgets('the Stock Manager sees the page but no Pay control', (
    tester,
  ) async {
    final repository = _StubRepository(summary: const [_summaryRow]);
    await _pump(
      tester,
      InventoryPayablesPage(
        viewmodel: PayablesViewmodel(repository: repository),
      ),
    );

    expect(find.text('Cebu Steel Works'), findsWidgets);
    expect(find.text(formatPeso(2000)), findsWidgets);
    expect(
      _payButton(),
      findsNothing,
      reason: 'a Stock Manager cannot record a payment (server 403)',
    );
  });

  testWidgets('the Store Manager gets a Pay control on an unpaid bill only', (
    tester,
  ) async {
    final repository = _StubRepository(
      bills: [
        _bill(id: 4),
        _bill(
          id: 5,
          balance: 0,
          status: SupplierBillStatus.paid,
          overdue: false,
        ),
      ],
      summary: const [_summaryRow],
    );
    await _pump(
      tester,
      SalesPayablesPage(viewmodel: PayablesViewmodel(repository: repository)),
    );

    expect(_payButton(), findsOneWidget, reason: 'only bill 4 still owes');
  });

  testWidgets('a recorded payment refreshes the row', (tester) async {
    final repository = _StubRepository(summary: const [_summaryRow]);
    await _pump(
      tester,
      AdminPayablesPage(viewmodel: PayablesViewmodel(repository: repository)),
    );

    repository.bills = [_bill(balance: 0, status: SupplierBillStatus.paid)];

    await tester.tap(_payButton());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record payment'));
    await tester.pumpAndSettle();

    expect(repository.posted.single, {
      'bill': 4,
      'amount': '400.00',
      'method': 'CASH',
    });
    expect(find.text('Paid'), findsWidgets, reason: 'the row caught up');
    expect(_payButton(), findsNothing);
  });

  testWidgets('one bill opens its payment history', (tester) async {
    final repository = _StubRepository(
      bills: [
        _bill(
          payments: [
            SupplierPayment(
              id: 7,
              billId: 4,
              amount: 500,
              method: SupplierPaymentMethod.cash,
              methodCode: 'CASH',
              reference: 'CV-11',
              chequeNumber: null,
              chequeBank: null,
              chequeDate: null,
              paidByName: 'Maria Santos',
              paidOn: DateTime(2026, 10, 20, 9, 30),
            ),
          ],
        ),
      ],
      summary: const [_summaryRow],
    );
    await _pump(
      tester,
      SalesPayablesPage(viewmodel: PayablesViewmodel(repository: repository)),
    );

    await tester.ensureVisible(find.text('Bill #4'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bill #4'));
    await tester.pumpAndSettle();

    expect(find.text('PAYMENT HISTORY'), findsOneWidget);
    expect(find.textContaining('Maria Santos'), findsOneWidget);
    expect(find.text(formatPeso(500)), findsWidgets);
  });

  testWidgets('760 px at 1.3x text, the page and the dialog render whole', (
    tester,
  ) async {
    final repository = _StubRepository(summary: const [_summaryRow]);
    await _pump(
      tester,
      SalesPayablesPage(viewmodel: PayablesViewmodel(repository: repository)),
      size: const Size(760, 900),
      scale: 1.3,
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Payables'), findsWidgets);

    // The bills panel sits under the summary, so at 760 x 900 the row action is
    // below the fold: scroll to it the way a reader would.
    await tester.ensureVisible(_payButton());
    await tester.pumpAndSettle();
    await tester.tap(_payButton());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.widgetWithText(FilledButton, 'Record payment').hitTestable(),
      findsOneWidget,
    );
  });

  // Phase 8 F3 (decision 20): the screen is three TABS, and the money a manager
  // needs on the same page — supplier credit and the cheque queue — is one click
  // away instead of on another screen.
  group('tabs', () {
    testWidgets('the screen offers Bills, Credit notes and Supplier cheques', (
      tester,
    ) async {
      await _pump(
        tester,
        SalesPayablesPage(
          viewmodel: PayablesViewmodel(repository: _StubRepository()),
        ),
      );

      expect(find.byKey(const ValueKey('payables-tab-bills')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('payables-tab-credit-notes')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('payables-tab-cheques')),
        findsOneWidget,
      );
    });

    testWidgets('the Credit notes tab lists what is left to spend', (
      tester,
    ) async {
      final repository = _StubRepository()..creditNotes = [_note()];
      await _pump(
        tester,
        SalesPayablesPage(viewmodel: PayablesViewmodel(repository: repository)),
      );

      await tester.tap(find.byKey(const ValueKey('payables-tab-credit-notes')));
      await tester.pumpAndSettle();

      expect(find.text('CN-20261113-0001'), findsWidgets);
      expect(find.text(formatPeso(200)), findsWidgets, reason: 'remaining');
    });

    testWidgets('the Supplier cheques tab is the manager\'s queue', (
      tester,
    ) async {
      final repository = _StubRepository()
        ..chequeRows = [
          SupplierPayment(
            id: 7,
            billId: 4,
            amount: 400,
            method: SupplierPaymentMethod.cheque,
            methodCode: 'CHEQUE',
            reference: '',
            chequeNumber: '000123',
            chequeBank: 'BDO',
            chequeDate: DateTime(2026, 10, 20),
            paidByName: 'Maria Santos',
            paidOn: DateTime(2026, 10, 21),
            status: SupplierPaymentStatus.issued,
            statusCode: 'ISSUED',
          ),
        ];
      await _pump(
        tester,
        SalesPayablesPage(viewmodel: PayablesViewmodel(repository: repository)),
      );

      await tester.tap(find.byKey(const ValueKey('payables-tab-cheques')));
      await tester.pumpAndSettle();

      expect(find.textContaining('000123'), findsWidgets);
      expect(find.widgetWithText(TextButton, 'Clear'), findsOneWidget);
    });

    testWidgets('the summary shows unapplied credit as its own column', (
      tester,
    ) async {
      await _pump(
        tester,
        SalesPayablesPage(
          viewmodel: PayablesViewmodel(
            repository: _StubRepository(
              summary: const [
                SupplierPayable(
                  supplierId: 2,
                  supplierName: 'Cebu Steel Works',
                  billCount: 1,
                  original: 900,
                  paid: 500,
                  balance: 200,
                  overdue: 0,
                  credited: 200,
                  unappliedCredit: 150,
                  issuedCheques: 100,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Unapplied credit'), findsOneWidget);
      expect(find.text(formatPeso(150)), findsOneWidget);
    });

    testWidgets('a bill settled with credit names the note in its history', (
      tester,
    ) async {
      final repository = _StubRepository(
        bills: [
          _bill(
            payments: [
              SupplierPayment(
                id: 7,
                billId: 4,
                amount: 200,
                method: SupplierPaymentMethod.credit,
                methodCode: 'CREDIT',
                reference: '',
                chequeNumber: null,
                chequeBank: null,
                chequeDate: null,
                paidByName: 'Maria Santos',
                paidOn: DateTime(2026, 11, 13),
                status: SupplierPaymentStatus.cleared,
                statusCode: 'CLEARED',
                creditNoteId: 12,
              ),
            ],
          ),
        ],
      )..creditNotes = [_note()];
      await _pump(
        tester,
        SalesPayablesPage(viewmodel: PayablesViewmodel(repository: repository)),
      );

      await tester.tap(find.text('Bill #4'));
      await tester.pumpAndSettle();

      expect(find.textContaining('CN-20261113-0001'), findsOneWidget);
    });
  });
}
