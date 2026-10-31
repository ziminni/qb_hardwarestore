// FX2 (wave-1 review I2): the store manager's plan asked for date range chips
// (Today, This week, This month) over the rows already loaded, so a manager can
// review one day or one refund without reading the whole list.
//
// The range is a client filter, never a fetch, so the clock is injected: a test
// that read the wall clock would pass in October and fail in November.

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/sales/widgets/sales_transactions_content.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Friday, 30 October 2026, 3 PM. The week it sits in starts Monday the 26th.
final _now = DateTime(2026, 10, 30, 15);

/// The caption that says a range covers the loaded rows, not the server's.
const _caption = 'Date ranges count only the transactions already loaded.';

void main() {
  Future<void> pumpContent(
    WidgetTester tester, {
    SalesTransactionsRole role = SalesTransactionsRole.storeManager,
    List<InventorySale>? sales,
  }) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SalesTransactionsContent(
            role: role,
            sales: sales ?? _sales(),
            now: () => _now,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Scoped to the bar: a status or the word Refunded also sits in the rows.
  Future<void> tapChip(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(of: find.byType(FilterBar), matching: find.text(label)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the date chips narrow the loaded rows at a fixed now', (
    tester,
  ) async {
    await pumpContent(tester);

    expect(find.text(_caption), findsOneWidget);
    // Everything, until a range is chosen.
    for (final no in _all) {
      expect(find.text(no), findsOneWidget, reason: no);
    }

    await tapChip(tester, 'Today');
    expect(find.text('TRX-20261030-0001'), findsOneWidget);
    for (final no in _all.where((no) => no != 'TRX-20261030-0001')) {
      expect(find.text(no), findsNothing, reason: 'Today keeps only today');
    }

    await tapChip(tester, 'All dates');
    await tapChip(tester, 'This week');
    expect(find.text('TRX-20261026-0003'), findsOneWidget, reason: 'Monday');
    expect(
      find.text('TRX-20261025-0002'),
      findsNothing,
      reason: 'Sunday belongs to last week: the week starts Monday',
    );

    await tapChip(tester, 'This month');
    expect(
      find.text('TRX-20261025-0002'),
      findsOneWidget,
      reason: 'same month',
    );
    expect(find.text('TRX-20260930-0001'), findsNothing, reason: 'last month');

    await tapChip(tester, 'All dates');
    for (final no in _all) {
      expect(find.text(no), findsOneWidget, reason: no);
    }
  });

  testWidgets('a date chip combines with a status chip and the search text', (
    tester,
  ) async {
    await pumpContent(tester);

    await tapChip(tester, 'Refunded');
    await tapChip(tester, 'This month');
    expect(find.text('TRX-20261025-0002'), findsOneWidget);
    expect(
      find.text('TRX-20261020-0004'),
      findsOneWidget,
      reason: 'a refund earlier in the month',
    );
    expect(
      find.text('TRX-20261030-0001'),
      findsNothing,
      reason: 'completed sales are filtered out by the status chip',
    );

    await tapChip(tester, 'This week');
    expect(
      find.text('TRX-20261020-0004'),
      findsNothing,
      reason: 'the week chip and the status chip must both hold',
    );
    expect(
      find.text('TRX-20261025-0002'),
      findsNothing,
      reason: 'Sunday is last week, so no refund survives the AND',
    );
    expect(
      find.text('No transactions match these filters.'),
      findsOneWidget,
      reason: 'an empty filter is not an empty system',
    );
  });

  testWidgets('the cashier keeps status and search only', (tester) async {
    await pumpContent(tester, role: SalesTransactionsRole.cashier);

    expect(find.text('Today'), findsNothing);
    expect(find.text('This week'), findsNothing);
    expect(find.text(_caption), findsNothing);
  });
}

/// Four sale dates that a range can tell apart: today, two days back, the
/// Monday the week starts on, the Sunday before it, and one in September.
const _all = [
  'TRX-20261030-0001',
  'TRX-20261028-0002',
  'TRX-20261026-0003',
  'TRX-20261025-0002',
  'TRX-20261020-0004',
  'TRX-20260930-0001',
];

List<InventorySale> _sales() => [
  _sale(
    no: 'TRX-20261030-0001',
    at: DateTime(2026, 10, 30, 14, 14),
    status: InventorySaleStatus.completed,
  ),
  _sale(
    no: 'TRX-20261028-0002',
    at: DateTime(2026, 10, 28, 10),
    status: InventorySaleStatus.completed,
  ),
  // Monday of the week the test's now sits in.
  _sale(
    no: 'TRX-20261026-0003',
    at: DateTime(2026, 10, 26, 8),
    status: InventorySaleStatus.completed,
  ),
  // Sunday before it: last week, same month.
  _sale(
    no: 'TRX-20261025-0002',
    at: DateTime(2026, 10, 25, 18),
    status: InventorySaleStatus.refunded,
  ),
  _sale(
    no: 'TRX-20261020-0004',
    at: DateTime(2026, 10, 20, 9),
    status: InventorySaleStatus.refunded,
  ),
  _sale(
    no: 'TRX-20260930-0001',
    at: DateTime(2026, 9, 30, 9),
    status: InventorySaleStatus.completed,
  ),
];

InventorySale _sale({
  required String no,
  required DateTime at,
  required InventorySaleStatus status,
}) => InventorySale(
  transactionNo: no,
  date: at,
  customer: 'Dela Cruz Construction',
  cashier: 'Ana Reyes',
  paymentMethod: 'Cash',
  source: 'Walk-in',
  status: status,
  lines: const [
    InventorySaleLine(
      productName: 'Portland Cement',
      variantName: '40 kg bag',
      sku: 'CEM-40KG',
      quantity: 2,
      unitPrice: 250,
    ),
  ],
  payments: const [InventorySalePayment(method: 'Cash', amount: 500)],
);
