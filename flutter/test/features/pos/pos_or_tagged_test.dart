// Store-ops Phase 1 follow-up: the till's OR-tagged tab.
//
// WHAT THIS PINS: the tab renders the shared cashier list grouped by whether the
// paper OR number is on the slip, and an UNTAGGED row carries the Attach action
// that starts the tagging (the badge on a tagged row is the proof it took).
//
// WHAT IT DOES NOT PROVE: that the server stores the number or that the slip
// reprints it — that is `pos_invoice_tagging_test.dart`.

import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/views/pos_or_tagged_page.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/transactions_fixtures.dart';

/// One sale whose paper OR was (or was not) tagged later.
TransactionRecord _sale({
  required int id,
  required String no,
  String? invoiceNo,
}) => TransactionRecord(
  id: id,
  transactionNo: no,
  orNumber: 'OS-00000$id',
  transDate: DateTime(2026, 11, 22, 14, id),
  customerId: 1,
  customerName: 'Juan Dela Cruz',
  cashierName: 'Ana Reyes',
  source: 'WALK_IN',
  originalTransactionId: null,
  status: 'COMPLETED',
  invoiceNo: invoiceNo,
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

const String _taggedRow = 'TRX-OR-TAGGED-01';
const String _untaggedRow = 'TRX-OR-UNTAGGED-01';

void main() {
  late InventorySalesViewmodel viewmodel;

  setUp(() {
    viewmodel = InventorySalesViewmodel(
      service: StubSalesService(
        rows: [
          _sale(id: 1, no: _taggedRow, invoiceNo: 'INV-0001'),
          _sale(id: 2, no: _untaggedRow),
        ],
      ),
    );
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      transactionsApp(
        child: const PosOrTaggedPage(),
        viewmodel: viewmodel,
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder chip(String label) => find.descendant(
    of: find.byType(FilterBar),
    matching: find.text(label),
  );

  testWidgets('the tab renders the cashier list under its own sidebar row', (
    tester,
  ) async {
    await pump(tester);

    for (final label in const ['All', 'OR-tagged', 'Untagged']) {
      expect(chip(label), findsOneWidget, reason: 'chip $label');
    }
    expect(
      find.widgetWithText(DashboardShell, 'OR-tagged'),
      findsWidgets,
      reason: 'the shell names the tab',
    );
    final shell = tester.widget<DashboardShell>(
      find.byType(DashboardShell).first,
    );
    expect(
      shell.selectedNavigationIndex,
      AppDestinations.indexOf('pos.or-tagged', AppAreas.pos),
      reason: 'the tab must light up its own row, not Transaction history',
    );
  });

  testWidgets('the OR-tagged chip keeps only the slips with a paper OR', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(_taggedRow), findsOneWidget);
    expect(find.text(_untaggedRow), findsOneWidget);

    await tester.tap(chip('OR-tagged'));
    await tester.pumpAndSettle();

    expect(find.text(_taggedRow), findsOneWidget);
    expect(
      find.text(_untaggedRow),
      findsNothing,
      reason: 'an untagged slip is not OR-tagged',
    );
  });

  testWidgets('the Untagged chip keeps only the slips with no OR yet', (
    tester,
  ) async {
    await pump(tester);

    await tester.tap(chip('Untagged'));
    await tester.pumpAndSettle();

    expect(find.text(_untaggedRow), findsOneWidget);
    expect(find.text(_taggedRow), findsNothing);
  });

  testWidgets('a tagged row shows its OR badge and no Attach action', (
    tester,
  ) async {
    await pump(tester);

    final row = find.byKey(const ValueKey(_taggedRow));
    expect(
      find.descendant(of: row, matching: find.text('OR INV-0001')),
      findsOneWidget,
      reason: 'the number the cashier typed has to be readable back',
    );
    expect(
      find.descendant(of: row, matching: find.text('Attach')),
      findsNothing,
      reason: 'a slip that already carries an OR cannot be tagged twice',
    );
  });

  testWidgets('an untagged row offers Attach and it opens the attach dialog', (
    tester,
  ) async {
    await pump(tester);

    final attach = find.descendant(
      of: find.byKey(const ValueKey(_untaggedRow)),
      matching: find.text('Attach'),
    );
    expect(attach, findsOneWidget);

    await tester.tap(attach);
    await tester.pumpAndSettle();

    expect(
      find.text('Attach OR invoice'),
      findsOneWidget,
      reason: 'the row action opens the same dialog the history tab uses',
    );
  });
}
