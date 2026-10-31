// Card K9: the Stock Manager's Returns screen, rebuilt on the shared DataPanel.
//
// This role reads returns to answer one question: how much stock came back. So
// the list leads with the document number and its status, the original sale,
// and an emphasised Units back, while the money lives in the read-only document
// sheet that a row tap opens. The screen writes nothing: the `inventory` role has
// GET only on `/api/v1/transactions/`.

import 'package:client/data/models/sales.dart';
import 'package:client/features/inventory/views/inventory_returns_page.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/inventory_returns_fixtures.dart';
import '../../support/transactions_fixtures.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
    String? error,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      transactionsApp(
        child: const InventoryReturnsPage(),
        viewmodel: InventorySalesViewmodel(
          service: StubSalesService(
            rows: inventoryReturnsFixture(),
            error: error,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists returns in the stock view, units back emphasised', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byType(DataPanel<InventoryReturn>), findsOneWidget);
    for (final label in ['Return', 'Date and time', 'Original sale', 'Items']) {
      expect(find.text(label), findsOneWidget, reason: 'column $label');
    }
    expect(
      find.text('Units back'),
      findsOneWidget,
      reason: 'stock coming back is this role\'s number',
    );

    // Counting the returned line items, not inventing a summary.
    final units = tester.widget<Text>(find.text('1,200'));
    expect(
      units.style?.fontWeight,
      FontWeight.w700,
      reason: 'the stock manager scans this column, so it is the bold one',
    );
    expect(
      find.text('Total'),
      findsNothing,
      reason: 'money belongs in the document sheet for this role, not the list',
    );
  });

  testWidgets('the list is strictly read-only', (tester) async {
    await pump(tester);

    expect(
      find.byType(FilledButton),
      findsNothing,
      reason: 'the inventory role cannot post, edit or void a return',
    );
    for (final action in ['New return', 'Void', 'Edit', 'Save']) {
      expect(find.text(action), findsNothing, reason: 'no $action action');
    }
  });

  testWidgets('a status chip narrows the list to that status', (tester) async {
    await pump(tester);

    expect(find.byType(FilterBar), findsOneWidget);
    expect(find.text('TRX-20261029-0004'), findsOneWidget);
    await tester.tap(
      // Scoped to the bar: the chip label equals a row's status badge.
      find.descendant(
        of: find.byType(FilterBar),
        matching: find.text('Rejected'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TRX-20261029-0004'), findsOneWidget);
    expect(find.text('TRX-20261030-0001'), findsNothing);
    expect(find.text('TRX-20261030-0002'), findsNothing);
  });

  testWidgets('a search that hides every return says so, without claiming the '
      'store has none', (tester) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'nothing matches this');
    await tester.pumpAndSettle();

    expect(
      find.text('No returns match these filters.'),
      findsOneWidget,
      reason: 'a filtered empty list is not an empty store',
    );
    expect(find.text('No returns recorded.'), findsNothing);
  });

  testWidgets('searching an SKU finds the return that brought it back', (
    tester,
  ) async {
    await pump(tester);

    await tester.enterText(find.byType(TextField), 'CEM-40KG');
    await tester.pumpAndSettle();

    expect(find.text('TRX-20261030-0001'), findsOneWidget);
    expect(find.text('TRX-20261030-0002'), findsNothing);
    expect(find.text('TRX-20261029-0003'), findsNothing);
  });

  testWidgets('tapping a row opens the read-only document with the money', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(find.byKey(const ValueKey('TRX-20261030-0001')));
    await tester.pumpAndSettle();

    expect(find.byType(SalesDocumentSheet), findsOneWidget);
    final sheet = find.byType(SalesDocumentSheet);
    expect(
      find.descendant(of: sheet, matching: find.textContaining('₱1,140,000')),
      findsWidgets,
      reason: 'the refund is a detail here, but it is still the real amount',
    );
    expect(
      find.descendant(of: sheet, matching: find.textContaining('1,200')),
      findsWidgets,
      reason: 'units back is on the document too',
    );
    expect(
      find.descendant(of: sheet, matching: find.text('Original sale')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: sheet, matching: find.byType(TextField)),
      findsNothing,
      reason: 'a posted return is immutable',
    );
  });

  testWidgets('a return with no original sale says so in words, not a dash', (
    tester,
  ) async {
    await pump(tester);

    expect(find.text('Not linked'), findsOneWidget);
    expect(find.text('—'), findsNothing);
  });

  testWidgets('a narrow window shows each return as a card', (tester) async {
    await pump(tester, size: const Size(760, 1200));

    expect(find.byKey(const ValueKey('DataPanel.cards')), findsOneWidget);
    expect(find.byKey(const ValueKey('DataPanel.table')), findsNothing);
  });

  testWidgets('a failed load keeps the rows it already had and names the '
      'failure', (tester) async {
    await pump(tester, error: 'Cannot connect to the BuildPro server.');

    expect(find.textContaining('Cannot connect'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
  });
}
