// The shared report viewer draws graphs, not only tiles and a table: a sales
// trend for the summary, bars per item, bars per cashier, and a tender split on
// bill-wise. A report with nothing to plot says so in words and never throws.
//
// Stub repositories answer like the server does, so the viewer renders real
// numbers without a backend.

import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/features/reports/report_catalogue.dart';
import 'package:client/features/reports/report_viewer_page.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Map<String, dynamic> _paged({
  required Map<String, dynamic> totals,
  required List<Map<String, dynamic>> results,
}) => {
  'from': '2026-10-01',
  'to': '2026-10-30',
  'totals': totals,
  'count': results.length,
  'next': null,
  'previous': null,
  'results': results,
};

/// Real numbers for every chart the viewer draws.
class _StubChartRepository extends ReportsRepository {
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
            day: '2026-10-28',
            transactions: 1,
            gross: 500,
            vat: 60,
            discounts: 20,
            paymentFees: 0,
            deliveryFees: 0,
          ),
          SalesDay(
            day: '2026-10-29',
            transactions: 2,
            gross: 1000,
            vat: 120,
            discounts: 30,
            paymentFees: 0,
            deliveryFees: 0,
          ),
        ],
      );

  @override
  Future<SalesByItemReport> fetchSalesByItem({
    String? from,
    String? to,
  }) async => SalesByItemReport.fromJson(
    _paged(
      totals: {
        'variant_count': 2,
        'qty_base': '10.00',
        'net_merchandise': '820.00',
        'cogs': '400.00',
        'gross_profit': '420.00',
        'missing_cost_deductions': 0,
      },
      results: [
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
        {
          'variant_uom_id': 2,
          'variant_id': 2,
          'sku': 'CHIPS-50',
          'product': 'Chips',
          'variant': '50g',
          'uom': 'PACK',
          'qty_sold': '4.00',
          'qty_base': '4.00',
          'merchandise_gross': '320.00',
          'discounts': '20.00',
          'net_merchandise': '300.00',
          'cogs': '100.00',
          'gross_profit': '200.00',
          'missing_cost_deductions': 0,
        },
      ],
    ),
  );

  @override
  Future<SalesByCashier> fetchSalesByCashier({
    String? from,
    String? to,
  }) async => SalesByCashier.fromJson(
    _paged(
      totals: {
        'transactions': 5,
        'invoice_total': '2500.00',
        'discounts': '80.00',
      },
      results: [
        {
          'cashier_id': 4,
          'cashier_name': 'Maria Santos',
          'username': 'maria',
          'transactions': 3,
          'invoice_total': '1500.00',
          'discounts': '50.00',
        },
        {
          'cashier_id': 5,
          'cashier_name': 'Jose Reyes',
          'username': 'jose',
          'transactions': 2,
          'invoice_total': '1000.00',
          'discounts': '30.00',
        },
      ],
    ),
  );

  @override
  Future<InventoryValuation> fetchInventoryValuation() async =>
      const InventoryValuation(
        batchCount: 1,
        totalUnits: 4,
        totalCost: 100,
        totalRetail: 150,
        categories: [
          ValuationCategory(
            id: 1,
            name: 'Drinks',
            batchCount: 1,
            units: 4,
            cost: 100,
            retail: 150,
          ),
        ],
      );

  @override
  Future<BillWiseReport> fetchBillWise({String? from, String? to}) async =>
      BillWiseReport.fromJson(
        _paged(
          totals: {
            'transactions': 2,
            'discount': '50.00',
            'grand_total': '2500.00',
            'methods': {'CASH': '1500.00', 'GCASH': '1000.00'},
          },
          results: [
            {
              'id': 9,
              'transaction_no': 'OS-0009',
              'or_number': 'OR-000123',
              'invoice_no': 'INV-0009',
              'date': '2026-10-29T14:14:00+08:00',
              'source': 'POS',
              'cashier_id': 4,
              'cashier_name': 'Maria Santos',
              'original_transaction_id': null,
              'methods': {'CASH': '1500.00'},
              'discount': '50.00',
              'grand_total': '1500.00',
            },
          ],
        ),
      );
}

/// The same reports, with nothing to plot: an empty range answers with empty
/// lists, not an error.
class _EmptyChartRepository extends ReportsRepository {
  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async =>
      const SalesSummary(
        from: '2026-10-01',
        to: '2026-10-30',
        totalTransactions: 0,
        totalGross: 0,
        totalVat: 0,
        totalDiscounts: 0,
        days: [],
      );

  @override
  Future<SalesByItemReport> fetchSalesByItem({
    String? from,
    String? to,
  }) async => SalesByItemReport.fromJson(
    _paged(
      totals: {
        'variant_count': 0,
        'qty_base': '0.00',
        'net_merchandise': '0.00',
        'cogs': '0.00',
        'gross_profit': '0.00',
        'missing_cost_deductions': 0,
      },
      results: const [],
    ),
  );

  @override
  Future<SalesByCashier> fetchSalesByCashier({
    String? from,
    String? to,
  }) async => SalesByCashier.fromJson(
    _paged(
      totals: {'transactions': 0, 'invoice_total': '0.00', 'discounts': '0.00'},
      results: const [],
    ),
  );

  @override
  Future<BillWiseReport> fetchBillWise({String? from, String? to}) async =>
      BillWiseReport.fromJson(
        _paged(
          totals: {
            'transactions': 0,
            'discount': '0.00',
            'grand_total': '0.00',
            'methods': <String, dynamic>{},
          },
          results: const [],
        ),
      );
}

Future<void> _open(
  WidgetTester tester,
  String id,
  ReportsRepository repository,
) async {
  await tester.pumpWidget(
    _host(
      ReportViewerView(
        key: ValueKey('viewer-$id-${repository.runtimeType}'),
        report: reportById(id)!,
        repository: repository,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('report viewer charts', () {
    testWidgets('sales summary draws a trend chart above the table', (
      tester,
    ) async {
      await _open(tester, 'sales-summary', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-sales-trend')),
        findsOneWidget,
        reason: 'the summary plots its per-day sales',
      );

      // Charts sit below the KPI tiles and above the data table.
      final tile = tester.getTopLeft(find.byType(MetricTile).first).dy;
      final chart = tester
          .getTopLeft(find.byKey(const ValueKey('report-viewer-sales-trend')))
          .dy;
      final table = tester
          .getTopLeft(find.byKey(const ValueKey('report-viewer-table')))
          .dy;
      expect(chart, greaterThan(tile));
      expect(chart, lessThan(table));
    });

    testWidgets('item-wise draws a bar chart per item', (tester) async {
      await _open(tester, 'item-wise', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-item-chart')),
        findsOneWidget,
      );
      expect(find.text('Coke · 1.5L'), findsWidgets);
    });

    testWidgets('cashier-wise draws a bar chart per cashier', (tester) async {
      await _open(tester, 'cashier', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-cashier-chart')),
        findsOneWidget,
      );
      expect(find.text('Jose Reyes'), findsWidgets);
    });

    testWidgets('bill-wise draws the tender split', (tester) async {
      await _open(tester, 'bill-wise', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-tender-split')),
        findsOneWidget,
      );
      expect(find.textContaining('Cash'), findsWidgets);
    });

    testWidgets('a range with nothing to plot says so instead of throwing', (
      tester,
    ) async {
      for (final id in ['sales-summary', 'item-wise', 'cashier', 'bill-wise']) {
        await _open(tester, id, _EmptyChartRepository());

        expect(
          find.text('No data for this range'),
          findsOneWidget,
          reason: '$id has an empty range',
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('a report with nothing plottable keeps tiles and table', (
      tester,
    ) async {
      await _open(tester, 'inventory-valuation', _StubChartRepository());

      expect(find.text('No data for this range'), findsNothing);
      expect(find.byKey(const ValueKey('report-viewer-table')), findsOneWidget);
    });
  });
}
