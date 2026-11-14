// Card S1: the store manager's Transactions page is the same shared content as
// the cashier's history, plus the Source column and a per-row View that opens the
// document sheet.

import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/views/sales_transactions_page.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/transactions_fixtures.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    InventorySalesViewmodel? viewmodel,
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      transactionsApp(
        child: const SalesTransactionsPage(),
        viewmodel:
            viewmodel ??
            InventorySalesViewmodel(
              service: StubSalesService(rows: transactionsFixture()),
            ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the shared content with the manager columns', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byType(DataPanel<InventorySale>), findsOneWidget);
    for (final label in ['Transaction', 'Date and time', 'Customer', 'Total']) {
      expect(find.text(label), findsOneWidget, reason: 'column $label');
    }
    expect(
      find.text('Requisition'),
      findsOneWidget,
      reason: 'where a sale came from is this role\'s extra fact',
    );
    expect(
      find.text('View'),
      findsWidgets,
      reason: 'the pinned View action still opens the document',
    );
  });

  // FX1 (wave-1 review I1): the manager lost how a sale was paid when the four
  // money columns became one panel. The method rides under the customer, the
  // way the sale's source does, so it shows at every width the table fits.
  testWidgets('the payment method rides under the customer', (tester) async {
    await pump(tester);

    expect(
      find.text('Cash'),
      findsOneWidget,
      reason: 'how the walk-in sale was paid',
    );
    expect(find.text('Bank transfer'), findsOneWidget);
    expect(
      find.text('No payment'),
      findsOneWidget,
      reason: 'the void sale carries no payment rows, and a word says so',
    );
  });

  // FX4 (wave-1 review I4) + F1 (Phase 4): the list sits in a bounded slot and
  // the shared panel pages it 25 rows at a time, so no 2,000 row layout is ever
  // built and the oldest sale is reached by paging, not by one endless scroll.
  testWidgets('a 2,000 row list pages, one page of rows at a time', (
    tester,
  ) async {
    await pump(tester, viewmodel: _manyRows());

    final built = _builtRows(tester);
    expect(
      built,
      lessThan(100),
      reason: 'eager layout would build all 2,000 cards and rows',
    );
    expect(find.text('1 to 25 of 2,000'), findsOneWidget);
    expect(find.byKey(const ValueKey('TRX-000001')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('TRX-000026')),
      findsNothing,
      reason: 'the 26th sale waits on page 2',
    );

    await tester.tap(find.byTooltip('Next page'));
    await tester.pumpAndSettle();

    expect(find.text('26 to 50 of 2,000'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('TRX-000026')),
      findsOneWidget,
      reason: 'the next page starts where the last one stopped',
    );
    expect(tester.takeException(), isNull);
  });

  for (final size in const [
    Size(1440, 900),
    Size(1440, 768),
    Size(1100, 900),
    Size(760, 900),
    Size(1366, 768),
  ]) {
    testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()}', (
      tester,
    ) async {
      await pump(tester, size: size);

      expect(
        tester.takeException(),
        isNull,
        reason: 'the filters sit above a bounded panel at every size',
      );
      expect(find.byType(DataPanel<InventorySale>), findsOneWidget);
    });
  }

  testWidgets('a status chip narrows the list to that status', (tester) async {
    await pump(tester);

    expect(find.byType(FilterBar), findsOneWidget);
    expect(find.text('TRX-20261030-0001'), findsOneWidget);
    await tester.tap(
      find.descendant(of: find.byType(FilterBar), matching: find.text('Void')),
    );
    await tester.pumpAndSettle();

    expect(find.text('TRX-20261029-0006'), findsOneWidget);
    expect(find.text('TRX-20261030-0001'), findsNothing);
  });

  testWidgets('tapping a row opens the document sheet', (tester) async {
    await pump(tester);

    expect(
      find.byKey(const ValueKey('TRX-20261030-0001')),
      findsOneWidget,
      reason: 'the row is the tap target',
    );
    await tester.tap(find.byKey(const ValueKey('TRX-20261030-0001')));
    await tester.pumpAndSettle();

    expect(find.byType(SalesDocumentSheet), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SalesDocumentSheet),
        matching: find.text('Reyes Trading'),
      ),
      findsNothing,
      reason: 'the sheet belongs to the row that was tapped',
    );
    expect(
      find.descendant(
        of: find.byType(SalesDocumentSheet),
        matching: find.text('Payment (Cash)'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a narrow window shows each sale as a card', (tester) async {
    await pump(tester, size: const Size(760, 1200));

    expect(find.byKey(const ValueKey('DataPanel.cards')), findsOneWidget);
    expect(find.byKey(const ValueKey('DataPanel.table')), findsNothing);
  });

  testWidgets('nothing loaded yet says so once', (tester) async {
    await pump(
      tester,
      viewmodel: InventorySalesViewmodel(service: StubSalesService()),
    );

    expect(find.text('No transactions found.'), findsOneWidget);
  });

  testWidgets('a failed load offers a retry', (tester) async {
    await pump(
      tester,
      viewmodel: InventorySalesViewmodel(
        service: StubSalesService(error: 'The sales list could not be loaded.'),
      ),
    );

    expect(find.text('The sales list could not be loaded.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(
      find.byType(ErrorBanner),
      findsOneWidget,
      reason: 'the one error surface, not a page-local red box',
    );
  });
}

/// The 40 pages the service can load, at the size that made eager layout hurt.
InventorySalesViewmodel _manyRows() => InventorySalesViewmodel(
  service: StubSalesService(
    rows: [
      for (var index = 1; index <= 2000; index++)
        TransactionRecord(
          id: index,
          transactionNo: 'TRX-${index.toString().padLeft(6, '0')}',
          transDate: DateTime(2026, 10, 30).subtract(Duration(minutes: index)),
          customerId: 3,
          customerName: 'Customer $index',
          cashierName: 'Ana Reyes',
          source: 'WALK_IN',
          originalTransactionId: null,
          status: 'COMPLETED',
          grandTotal: 100,
          items: const [
            TransactionLineItem(
              variantUomId: 42,
              variantUomCode: 'BAG',
              qty: 1,
              unitPrice: 100,
              subtotal: 100,
            ),
          ],
          payments: const [
            TransactionPayment(method: 'CASH', amountTendered: 100),
          ],
        ),
    ],
  ),
);

/// How many transaction rows the panel actually built: each carries its
/// document number as its key.
int _builtRows(WidgetTester tester) => tester
    .widgetList(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('TRX-'),
      ),
    )
    .length;
