import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/pos/views/pos_transaction_history_page.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/transactions_fixtures.dart';

class _MutableSalesService extends SalesService {
  _MutableSalesService(this.rows);

  List<TransactionRecord> rows;

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async =>
      rows;
}

class _StubVoidPosService extends PosService {
  int? voidedId;
  String? voidedReason;

  @override
  Future<void> voidTransaction(
    int transactionId, {
    required String reason,
  }) async {
    voidedId = transactionId;
    voidedReason = reason;
  }
}

TransactionRecord _bodegaSale({
  required int id,
  required String no,
  required String? bodegaStatus,
  String orNumber = 'OS-000123',
  String? invoiceNo,
}) => TransactionRecord(
  id: id,
  transactionNo: no,
  orNumber: orNumber,
  invoiceNo: invoiceNo,
  transDate: DateTime(2026, 11, 22, 14, 0),
  customerId: 1,
  customerName: 'Juan Dela Cruz',
  cashierName: 'Ana Reyes',
  source: 'WALK_IN',
  originalTransactionId: null,
  status: 'COMPLETED',
  bodegaStatus: bodegaStatus,
  grandTotal: 1000,
  items: const [
    TransactionLineItem(
      variantUomId: 45,
      variantUomCode: 'BAG',
      qty: 4,
      unitPrice: 250,
      subtotal: 1000,
    ),
  ],
  payments: const [TransactionPayment(method: 'CASH', amountTendered: 1000)],
);

void main() {
  late InventorySalesViewmodel viewmodel;

  setUp(() {
    viewmodel = InventorySalesViewmodel(
      service: StubSalesService(rows: transactionsFixture()),
    );
  });

  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    InventorySalesViewmodel? withViewmodel,
    PosService? posService,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      transactionsApp(
        child: PosTransactionHistoryPage(posService: posService),
        viewmodel: withViewmodel ?? viewmodel,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders remodeled cashier KPI strip and separated OR # column', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byType(DataPanel<InventorySale>), findsOneWidget);
    // 4-card KPI strip
    expect(find.text('TOTAL TRANSACTIONS'), findsOneWidget);
    expect(find.text('COMPLETED / SETTLED'), findsOneWidget);
    expect(find.text('UTANG / CREDIT'), findsOneWidget);
    expect(find.text('VOIDED & RETURNED'), findsOneWidget);

    // Remodeled cashier table columns (separate Transaction & OS # and OR #)
    for (final label in [
      'Transaction & OS #',
      'OR #',
      'Customer',
      'Items',
      'Payment',
      'Status',
      'Total',
      'Actions',
    ]) {
      expect(find.text(label), findsOneWidget, reason: 'column $label');
    }
    expect(find.text('Source'), findsNothing);
    expect(find.textContaining('BIR'), findsNothing);
    expect(find.text('Export CSV'), findsNothing);
    expect(find.text('Print Shift Log'), findsNothing);
  });

  testWidgets('OR # column displays actual OR value or None when untagged', (
    tester,
  ) async {
    final service = _MutableSalesService([
      _bodegaSale(
        id: 1,
        no: 'TRX-WITH-OR',
        bodegaStatus: null,
        orNumber: 'OS-20261125-0001',
        invoiceNo: 'OR-99104',
      ),
      _bodegaSale(
        id: 2,
        no: 'TRX-NO-OR',
        bodegaStatus: null,
        orNumber: 'OS-20261125-0002',
        invoiceNo: null,
      ),
    ]);
    await pump(tester, withViewmodel: InventorySalesViewmodel(service: service));

    final taggedRow = find.byKey(const ValueKey('TRX-WITH-OR'));
    expect(
      find.descendant(of: taggedRow, matching: find.text('OR-99104')),
      findsOneWidget,
    );

    final untaggedRow = find.byKey(const ValueKey('TRX-NO-OR'));
    expect(
      find.descendant(of: untaggedRow, matching: find.text('None')),
      findsOneWidget,
    );
  });

  testWidgets('segmented status pill narrows the list to that status', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('TRX-20261030-0001'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('cashier-history-filter-bar')),
        matching: find.textContaining('Refunded ('),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TRX-20261029-0007'), findsOneWidget);
    expect(
      find.text('TRX-20261030-0001'),
      findsNothing,
      reason: 'a completed sale is not a refund',
    );
  });

  testWidgets('tapping a row opens the document sheet', (tester) async {
    await pump(tester);

    expect(find.byType(SalesDocumentSheet), findsNothing);
    expect(
      find.byKey(const ValueKey('TRX-20261030-0002')),
      findsOneWidget,
      reason: 'the row is the tap target',
    );
    await tester.tap(find.byKey(const ValueKey('TRX-20261030-0002')));
    await tester.pumpAndSettle();

    expect(find.byType(SalesDocumentSheet), findsOneWidget);
    final sheet = find.byType(SalesDocumentSheet);
    expect(
      find.descendant(of: sheet, matching: find.text('TRX-20261030-0002')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.textContaining('₱1,140,000')),
      findsWidgets,
      reason: 'the seven digit total must survive the round trip',
    );
  });

  testWidgets('void button opens confirmation dialog and calls PosService.voidTransaction', (
    tester,
  ) async {
    final voidService = _StubVoidPosService();
    final salesService = _MutableSalesService([
      _bodegaSale(id: 42, no: 'TRX-VOID-ME', bodegaStatus: null),
    ]);
    await pump(
      tester,
      withViewmodel: InventorySalesViewmodel(service: salesService),
      posService: voidService,
    );

    await tester.tap(find.byKey(const ValueKey('void-sale-TRX-VOID-ME')));
    await tester.pumpAndSettle();

    expect(find.text('Void Transaction'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('void-reason-input')),
      'Duplicate entry',
    );
    await tester.tap(find.byKey(const ValueKey('void-confirm-button')));
    await tester.pumpAndSettle();

    expect(voidService.voidedId, 42);
    expect(voidService.voidedReason, 'Duplicate entry');
  });

  testWidgets('a narrow window shows each sale as a card', (tester) async {
    await pump(tester, size: const Size(760, 1200));

    expect(find.byKey(const ValueKey('DataPanel.cards')), findsOneWidget);
    expect(find.byKey(const ValueKey('DataPanel.table')), findsNothing);
    expect(find.text('TRX-20261030-0001'), findsOneWidget);
  });

  testWidgets(
    'Bodega status syncs across row badges, status chips, and an already-open dialog',
    (tester) async {
      final service = _MutableSalesService([
        _bodegaSale(id: 10, no: 'TRX-BODEGA-01', bodegaStatus: 'PENDING'),
        _bodegaSale(id: 11, no: 'TRX-BODEGA-02', bodegaStatus: 'PARTIAL'),
        _bodegaSale(id: 12, no: 'TRX-BODEGA-03', bodegaStatus: 'RELEASED'),
      ]);
      final vm = InventorySalesViewmodel(service: service);
      await pump(tester, size: const Size(1440, 1200), withViewmodel: vm);

      // Row 1 (PENDING): Pending Pickup + Awaiting Bodega
      final row1 = find.byKey(const ValueKey('TRX-BODEGA-01'));
      expect(
        find.descendant(of: row1, matching: find.text('Pending Pickup')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row1, matching: find.text('Awaiting Bodega')),
        findsOneWidget,
      );

      // Row 2 (PARTIAL): Partial Pickup + Bodega: Partial
      final row2 = find.byKey(const ValueKey('TRX-BODEGA-02'));
      expect(
        find.descendant(of: row2, matching: find.text('Partial Pickup')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row2, matching: find.text('Bodega: Partial')),
        findsOneWidget,
      );

      // Row 3 (RELEASED): Completed + Bodega: Released
      final row3 = find.byKey(const ValueKey('TRX-BODEGA-03'));
      expect(
        find.descendant(of: row3, matching: find.text('Completed')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row3, matching: find.text('Bodega: Released')),
        findsOneWidget,
      );

      // Segmented pill "Pending Pickup (2)" shows only PENDING + PARTIAL (not RELEASED).
      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('cashier-history-filter-bar')),
          matching: find.text('Pending Pickup (2)'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('TRX-BODEGA-01')), findsOneWidget);
      expect(find.byKey(const ValueKey('TRX-BODEGA-02')), findsOneWidget);
      expect(find.byKey(const ValueKey('TRX-BODEGA-03')), findsNothing);

      // Open row 1's dialog while still PENDING.
      await tester.tap(find.byKey(const ValueKey('TRX-BODEGA-01')));
      await tester.pumpAndSettle();

      final sheet = find.byType(SalesDocumentSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('Awaiting Bodega pickup')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Pending Pickup')),
        findsOneWidget,
      );

      // Simulate Bodega releasing row 1 (via app or SMS) while the dialog is OPEN.
      service.rows = [
        _bodegaSale(id: 10, no: 'TRX-BODEGA-01', bodegaStatus: 'RELEASED'),
        _bodegaSale(id: 11, no: 'TRX-BODEGA-02', bodegaStatus: 'PARTIAL'),
        _bodegaSale(id: 12, no: 'TRX-BODEGA-03', bodegaStatus: 'RELEASED'),
      ];
      await vm.load(silent: true);
      await tester.pumpAndSettle();

      // The already-open dialog updates live to Released (Picked up) + Completed!
      expect(
        find.descendant(of: sheet, matching: find.text('Released (Picked up)')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Completed')),
        findsOneWidget,
      );
    },
  );

  testWidgets('pagination splits rows by page size and navigates pages', (
    tester,
  ) async {
    final manyRows = [
      for (var i = 1; i <= 15; i++)
        _bodegaSale(
          id: i,
          no: 'TRX-PAGE-${i.toString().padLeft(2, '0')}',
          bodegaStatus: null,
        ),
    ];
    await pump(
      tester,
      size: const Size(1440, 1200),
      withViewmodel: InventorySalesViewmodel(
        service: _MutableSalesService(manyRows),
      ),
    );

    expect(find.text('1 to 10 of 15'), findsOneWidget);
    expect(find.byKey(const ValueKey('TRX-PAGE-01')), findsOneWidget);
    expect(find.byKey(const ValueKey('TRX-PAGE-11')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('DataPanel.next')));
    await tester.pumpAndSettle();

    expect(find.text('11 to 15 of 15'), findsOneWidget);
    expect(find.byKey(const ValueKey('TRX-PAGE-11')), findsOneWidget);
    expect(find.byKey(const ValueKey('TRX-PAGE-01')), findsNothing);
  });
}
