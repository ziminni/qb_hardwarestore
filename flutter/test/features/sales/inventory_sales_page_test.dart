// Card S1: the stock manager's Sales page is the shared content in its stock
// view: units out is the emphasised number and money lives in the details.

import 'package:client/data/models/sales.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/views/inventory_sales_page.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/transactions_fixtures.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      transactionsApp(
        child: const InventorySalesPage(),
        viewmodel: InventorySalesViewmodel(
          service: StubSalesService(rows: transactionsFixture()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the shared content in the stock view', (tester) async {
    await pump(tester);

    expect(find.byType(DataPanel<InventorySale>), findsOneWidget);
    for (final label in ['Transaction', 'Date and time', 'Items']) {
      expect(find.text(label), findsOneWidget, reason: 'column $label');
    }
    expect(
      find.text('Units out'),
      findsOneWidget,
      reason: 'stock leaving the warehouse is this role\'s number',
    );
    expect(
      find.text('1,200'),
      findsOneWidget,
      reason: 'units are a count, and counts carry thousands separators',
    );
    expect(
      find.text('Total'),
      findsNothing,
      reason: 'money belongs in the details for this role, not the list',
    );
  });

  testWidgets('a status chip narrows the list to that status', (tester) async {
    await pump(tester);

    expect(find.byType(FilterBar), findsOneWidget);
    expect(find.text('TRX-20261030-0001'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(FilterBar),
        matching: find.text('Completed'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TRX-20261030-0001'), findsOneWidget);
    expect(find.text('TRX-20261029-0007'), findsNothing);
    expect(find.text('TRX-20261029-0006'), findsNothing);
  });

  testWidgets('tapping a row opens the document with the money inside', (
    tester,
  ) async {
    await pump(tester);

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
      find.descendant(of: sheet, matching: find.textContaining('₱1,140,000')),
      findsWidgets,
      reason: 'the total is a detail here, but it is still the real total',
    );
    expect(
      find.descendant(of: sheet, matching: find.textContaining('1,200')),
      findsWidgets,
      reason: 'units out is on the document too',
    );
  });

  testWidgets('a narrow window shows each sale as a card', (tester) async {
    await pump(tester, size: const Size(760, 1200));

    expect(find.byKey(const ValueKey('DataPanel.cards')), findsOneWidget);
    expect(find.byKey(const ValueKey('DataPanel.table')), findsNothing);
  });
}
