// Card S1: the cashier's Transaction history is now a thin shell around the one
// shared transactions content. These tests pin the cashier's own column set (no
// Source), the status chips, the row tap that opens the document sheet and the
// card layout on a narrow window.

import 'package:client/data/models/sales.dart';
import 'package:client/features/pos/views/pos_transaction_history_page.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/transactions_fixtures.dart';

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
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      transactionsApp(
        child: const PosTransactionHistoryPage(),
        viewmodel: withViewmodel ?? viewmodel,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('renders the shared content with the cashier columns', (
    tester,
  ) async {
    await pump(tester);

    expect(find.byType(DataPanel<InventorySale>), findsOneWidget);
    for (final label in ['Transaction', 'Date and time', 'Customer', 'Total']) {
      expect(find.text(label), findsOneWidget, reason: 'column $label');
    }
    expect(find.text('Payment'), findsOneWidget);
    expect(
      find.text('Source'),
      findsNothing,
      reason: 'a cashier does not read where a sale came from',
    );
    expect(find.text('View'), findsNothing);
  });

  testWidgets('a status chip narrows the list to that status', (tester) async {
    await pump(tester);

    expect(find.byType(FilterBar), findsOneWidget);
    expect(find.text('TRX-20261030-0001'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(FilterBar),
        matching: find.text('Refunded'),
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

  testWidgets('a narrow window shows each sale as a card', (tester) async {
    await pump(tester, size: const Size(760, 1200));

    expect(find.byKey(const ValueKey('DataPanel.cards')), findsOneWidget);
    expect(find.byKey(const ValueKey('DataPanel.table')), findsNothing);
    expect(find.text('TRX-20261030-0001'), findsOneWidget);
  });
}
