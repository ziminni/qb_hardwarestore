// Card S1: the store manager's Transactions page is the same shared content as
// the cashier's history, plus the Source column and a per-row View that opens the
// document sheet.

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
