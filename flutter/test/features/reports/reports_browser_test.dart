// The Reports browser: an inner sidebar of reports on the left, the selected
// report on the right.
//
// The browser replaced the catalogue's card grid as the Reports front door, so
// what matters here is navigation, not the reports themselves: a manager sees
// the SALES and INVENTORY groups and the first report already loaded; picking
// another row swaps the body; the stocker's account sees INVENTORY only (no
// sales figures anywhere, decision 02-role-visibility); a group collapses to
// hide its rows; and a till-sized window trades the sidebar for a dropdown.

import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/features/reports/report_catalogue.dart';
import 'package:client/features/reports/reports_browser_page.dart';
import 'package:client/features/reports/reports_shell.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Answers the three reports the browser opens on its own, so the right pane
/// renders real content without a server.
class _StubBrowserRepository extends ReportsRepository {
  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async =>
      const SalesSummary(
        from: '2026-10-01',
        to: '2026-10-30',
        totalTransactions: 3,
        totalGross: 1500,
        totalVat: 180,
        totalDiscounts: 50,
        days: [
          SalesDay(
            day: '2026-10-29',
            transactions: 3,
            gross: 1500,
            vat: 180,
            discounts: 50,
          ),
        ],
        abv: 500,
        asp: 25.5,
        markdownPercent: 8.3,
      );

  @override
  Future<SalesByItemReport> fetchSalesByItem({
    String? from,
    String? to,
  }) async => SalesByItemReport.fromJson({
    'from': '2026-10-01',
    'to': '2026-10-30',
    'totals': {
      'variant_count': 1,
      'qty_base': '6.00',
      'net_merchandise': '520.00',
      'cogs': '300.00',
      'gross_profit': '220.00',
      'missing_cost_deductions': 0,
    },
    'count': 1,
    'next': null,
    'previous': null,
    'results': [
      {
        'variant_uom_id': 1,
        'variant_id': 1,
        'sku': 'COKE-15',
        'product': 'Coke',
        'variant': '1.5L',
        'uom': 'BTL',
        'qty_sold': '6.00',
        'qty_base': '6.00',
        'merchandise_gross': '600.00',
        'discounts': '80.00',
        'net_merchandise': '520.00',
        'cogs': '300.00',
        'gross_profit': '220.00',
        'missing_cost_deductions': 0,
      },
    ],
  });

  @override
  Future<InventoryValuation> fetchInventoryValuation() async =>
      const InventoryValuation(
        batchCount: 4,
        totalUnits: 10,
        totalCost: 500,
        totalRetail: 750,
        categories: [
          ValuationCategory(
            id: 1,
            name: 'Beverages',
            batchCount: 4,
            units: 10,
            cost: 500,
            retail: 750,
          ),
        ],
      );
}

/// A window wide enough for the sidebar (the sidebar/picker break is 860px).
void _useWideWindow(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1400, 1400);
  addTearDown(tester.view.reset);
}

/// A till-sized window: below the 860px break, so the dropdown replaces the
/// sidebar.
void _useNarrowWindow(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(700, 1600);
  addTearDown(tester.view.reset);
}

Widget _browser({
  ReportsShell shell = ReportsShell.sales,
  Set<String>? areas,
}) => ReportsBrowserView(
  shell: shell,
  areas: areas,
  repository: _StubBrowserRepository(),
);

void main() {
  testWidgets('the manager sees SALES and INVENTORY, first report loaded', (
    tester,
  ) async {
    _useWideWindow(tester);
    await tester.pumpWidget(_host(_browser()));
    await tester.pumpAndSettle();

    expect(find.text(ReportSection.sales.label), findsOneWidget);
    expect(find.text(ReportSection.inventory.label), findsOneWidget);
    // The KPI section has no endpoint behind any of its cards, so its empty
    // group draws nothing at all.
    expect(find.text(ReportSection.kpis.label), findsNothing);

    // Both groups list their reports as rows, not as a card grid.
    expect(
      find.byKey(const ValueKey('report-row-sales-summary')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('report-row-inventory-valuation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('report-row-sales-summary')),
      findsOneWidget,
      reason: 'the sidebar lists rows, the first of them the sales summary',
    );

    // The first available report is already open on the right.
    expect(
      find.byKey(const ValueKey('report-browser-sales-summary')),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(MetricTile, 'Average bill value'),
      findsOneWidget,
    );
  });

  testWidgets('tapping another row swaps the report on the right', (
    tester,
  ) async {
    _useWideWindow(tester);
    await tester.pumpWidget(_host(_browser()));
    await tester.pumpAndSettle();

    expect(find.text('Coke · 1.5L'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('report-row-item-wise')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('report-browser-item-wise')),
      findsOneWidget,
    );
    expect(
      // Scoped to the table: the item chart above it names the same item.
      find.descendant(
        of: find.byKey(const ValueKey('report-viewer-table')),
        matching: find.text('Coke · 1.5L'),
      ),
      findsOneWidget,
    );
    // The summary's own content is gone, not stacked under the new report.
    expect(
      find.byKey(const ValueKey('report-browser-sales-summary')),
      findsNothing,
    );
  });

  testWidgets('the stocker sees INVENTORY only, and no sales rows', (
    tester,
  ) async {
    _useWideWindow(tester);
    await tester.pumpWidget(
      _host(
        _browser(shell: ReportsShell.inventory, areas: const {'inventory'}),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(ReportSection.inventory.label), findsOneWidget);
    expect(find.text(ReportSection.sales.label), findsNothing);
    expect(
      find.byKey(const ValueKey('report-row-sales-summary')),
      findsNothing,
    );
    expect(find.text('Sales summary'), findsNothing);

    // The first inventory report is what opens.
    expect(
      find.byKey(const ValueKey('report-browser-inventory-valuation')),
      findsOneWidget,
    );
    expect(find.widgetWithText(MetricTile, 'Value at cost'), findsOneWidget);
  });

  testWidgets('collapsing a group hides its rows, and expanding brings them '
      'back', (tester) async {
    _useWideWindow(tester);
    await tester.pumpWidget(_host(_browser()));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('report-group-sales')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('report-row-sales-summary')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('report-row-item-wise')), findsNothing);
    // The other group is untouched, and the open report stays open.
    expect(
      find.byKey(const ValueKey('report-row-inventory-valuation')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('report-browser-sales-summary')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('report-group-sales')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('report-row-sales-summary')),
      findsOneWidget,
    );
  });

  testWidgets('a narrow window trades the sidebar for a dropdown', (
    tester,
  ) async {
    _useNarrowWindow(tester);
    await tester.pumpWidget(_host(_browser()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('report-picker')), findsOneWidget);
    // No sidebar group header and no row buttons in the narrow layout.
    expect(find.text(ReportSection.sales.label), findsNothing);
    expect(
      find.byKey(const ValueKey('report-row-sales-summary')),
      findsNothing,
    );
    // The first report still renders below the picker.
    expect(
      find.byKey(const ValueKey('report-browser-sales-summary')),
      findsOneWidget,
    );
  });
}
