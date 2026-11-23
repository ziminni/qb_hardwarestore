// Reports suite P1 stage 2: the seven sales detail reports behind the shared
// viewer — item-wise, hourly, cashier, bill-wise, returns, discounts, voids.
//
// Every card that used to be a P1 placeholder now opens the ONE viewer over a
// live endpoint, so the catalogue flags, the paginated models, the tiles'
// locked wording and the disabled Excel button are all checked here.

import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/features/reports/report_catalogue.dart';
import 'package:client/features/reports/report_viewer_page.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The seven sales detail report ids, as the catalogue names them.
const List<String> _salesDetailIds = [
  'item-wise',
  'hourly',
  'cashier',
  'bill-wise',
  'returns',
  'discounts',
  'voids',
];

/// The `_paged()` envelope every one of the seven answers with.
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

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

/// Answers all seven sales detail reports off one canned page each, so the
/// viewer renders real rows without a server.
class _StubSalesDetailRepository extends ReportsRepository {
  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async =>
      const SalesSummary(
        from: '2026-10-01',
        to: '2026-10-30',
        totalTransactions: 3,
        totalGross: 1500,
        totalVat: 180,
        totalDiscounts: 50,
        days: [],
        abv: 500,
        asp: 25.5,
        markdownPercent: 8.3,
      );

  @override
  Future<SalesByItemReport> fetchSalesByItem({
    String? from,
    String? to,
  }) async => SalesByItemReport.fromJson(
    _paged(
      totals: {
        'variant_count': 1,
        'qty_base': '6.00',
        'net_merchandise': '520.00',
        'cogs': '300.00',
        'gross_profit': '220.00',
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
      ],
    ),
  );

  @override
  Future<SalesByHour> fetchSalesByHour({String? from, String? to}) async =>
      SalesByHour.fromJson(
        _paged(
          totals: {'transactions': 3, 'invoice_total': '1500.00'},
          results: [
            {'hour': 14, 'transactions': 3, 'invoice_total': '1500.00'},
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
        'transactions': 3,
        'invoice_total': '1500.00',
        'discounts': '50.00',
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
      ],
    ),
  );

  @override
  Future<BillWiseReport> fetchBillWise({String? from, String? to}) async =>
      BillWiseReport.fromJson(
        _paged(
          totals: {
            'transactions': 1,
            'discount': '50.00',
            'grand_total': '1500.00',
            'methods': {'CASH': '1500.00'},
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

  @override
  Future<ReturnsExchangesReport> fetchReturnsExchanges({
    String? from,
    String? to,
  }) async => ReturnsExchangesReport.fromJson(
    _paged(
      totals: {
        'transactions': 1,
        'returns': 1,
        'exchanges': 0,
        'refunded': '120.00',
      },
      results: [
        {
          'id': 11,
          'transaction_no': 'RT-0011',
          'date': '2026-10-29T15:00:00+08:00',
          'source': 'RETURN',
          'cashier_id': 4,
          'cashier_name': 'Maria Santos',
          'original_transaction_id': 9,
          'original_transaction_no': 'OS-0009',
          'refunded': '120.00',
          'grand_total': '-120.00',
          'reason': 'Flat Coke',
        },
      ],
    ),
  );

  @override
  Future<DiscountsReport> fetchDiscounts({String? from, String? to}) async =>
      DiscountsReport.fromJson(
        _paged(
          totals: {
            'line_discount': '50.00',
            'cart_discount': '30.00',
            'approval_discount': '30.00',
            'approvals': 2,
            'total_discount': '80.00',
          },
          results: [
            {'type': 'LINE', 'transactions': 3, 'total_discount': '50.00'},
          ],
        ),
      );

  @override
  Future<VoidsReport> fetchVoids({String? from, String? to}) async =>
      VoidsReport.fromJson(
        _paged(
          totals: {'transactions': 1, 'voided_total': '300.00'},
          results: [
            {
              'id': 12,
              'transaction_no': 'OS-0012',
              'date': '2026-10-30T09:30:00+08:00',
              'cashier_id': 4,
              'cashier_name': 'Maria Santos',
              'voided_total': '300.00',
              'reason': 'Wrong item scanned',
            },
          ],
        ),
      );
}

/// Item-wise with one row whose cost was never recorded, so the viewer has to
/// say the cost is unknown instead of printing a zero-peso cost.
class _UncostedItemRepository extends _StubSalesDetailRepository {
  @override
  Future<SalesByItemReport> fetchSalesByItem({
    String? from,
    String? to,
  }) async => SalesByItemReport.fromJson(
    _paged(
      totals: {
        'variant_count': 1,
        'qty_base': '6.00',
        'net_merchandise': '520.00',
        'cogs': null,
        'gross_profit': null,
        'missing_cost_deductions': 6,
      },
      results: [
        {
          'variant_uom_id': 2,
          'variant_id': 2,
          'sku': 'CHIPS-50',
          'product': 'Chips',
          'variant': '50g',
          'uom': 'PACK',
          'qty_sold': '6.00',
          'qty_base': '6.00',
          'merchandise_gross': '600.00',
          'discounts': '80.00',
          'net_merchandise': '520.00',
          'cogs': null,
          'gross_profit': null,
          'missing_cost_deductions': 6,
        },
      ],
    ),
  );
}

void main() {
  test('the seven sales detail cards are live', () {
    for (final id in _salesDetailIds) {
      expect(
        reportById(id)!.available,
        isTrue,
        reason: '$id has an endpoint behind it, so its card must open',
      );
    }
  });

  test(
    'the range and the totals sit outside the page, so paging keeps them',
    () {
      final report = SalesByItemReport.fromJson(
        _paged(
          totals: {
            'variant_count': 2,
            'qty_base': '9.50',
            'net_merchandise': '900.00',
            'cogs': null,
            'gross_profit': null,
            'missing_cost_deductions': 4,
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
              'cogs': null,
              'gross_profit': null,
              'missing_cost_deductions': 4,
            },
          ],
        ),
      );

      expect(report.from, '2026-10-01');
      expect(report.to, '2026-10-30');
      expect(report.variantCount, 2);
      expect(report.totalQtyBase, 9.5);
      expect(report.totalNet, 900.0);
      // A unit with no costed deduction reads as "unknown", never as ₱0 profit.
      expect(report.totalCogs, isNull);
      expect(report.totalGrossProfit, isNull);
      expect(report.missingCostDeductions, 4);
      expect(report.page.count, 1);
      expect(report.page.rows.single.sku, 'COKE-15');
      expect(report.page.rows.single.net, 520.0);
    },
  );

  test('every hour is a row, so an empty hour reads as zero', () {
    final report = SalesByHour.fromJson(
      _paged(
        totals: {'transactions': 0, 'invoice_total': null},
        results: [
          {'hour': 0, 'transactions': 0, 'invoice_total': '0.00'},
          {'hour': 23, 'transactions': 0, 'invoice_total': '0.00'},
        ],
      ),
    );

    expect(report.page.count, 2);
    expect(report.totalTransactions, 0);
    expect(report.totalInvoice, 0.0);
    expect(report.page.rows.map((row) => row.hour), [0, 23]);
  });

  test('bill-wise keeps every tender and the signed bill total', () {
    final report = BillWiseReport.fromJson(
      _paged(
        totals: {
          'transactions': 1,
          'discount': '50.00',
          'grand_total': '1500.00',
          'methods': {'CASH': '1400.00', 'GCASH': '100.00'},
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
            'methods': {'CASH': '1400.00', 'GCASH': '100.00'},
            'discount': '50.00',
            'grand_total': '1500.00',
          },
        ],
      ),
    );

    final row = report.page.rows.single;
    expect(row.transactionNo, 'OS-0009');
    expect(row.orNumber, 'OR-000123');
    expect(row.methods, {'CASH': 1400.0, 'GCASH': 100.0});
    expect(row.grandTotal, 1500.0);
    expect(report.totalDiscount, 50.0);
    expect(report.totalGrand, 1500.0);
  });

  test('returns count refunded money as positive, an exchange as zero', () {
    final report = ReturnsExchangesReport.fromJson(
      _paged(
        totals: {
          'transactions': 2,
          'returns': 1,
          'exchanges': 1,
          'refunded': '120.00',
        },
        results: [
          {
            'id': 11,
            'transaction_no': 'RT-0011',
            'date': '2026-10-29T15:00:00+08:00',
            'source': 'RETURN',
            'cashier_id': 4,
            'cashier_name': 'Maria Santos',
            'original_transaction_id': 9,
            'original_transaction_no': 'OS-0009',
            'refunded': '120.00',
            'grand_total': '-120.00',
            'reason': null,
          },
          {
            'id': 12,
            'transaction_no': 'EX-0012',
            'date': '2026-10-29T16:00:00+08:00',
            'source': 'EXCHANGE',
            'cashier_id': 4,
            'cashier_name': 'Maria Santos',
            'original_transaction_id': 9,
            'original_transaction_no': 'OS-0009',
            'refunded': '0.00',
            'grand_total': '0.00',
            'reason': 'Size swap',
          },
        ],
      ),
    );

    expect(report.totalReturns, 1);
    expect(report.totalExchanges, 1);
    expect(report.totalRefunded, 120.0);
    expect(report.page.rows.first.originalTransactionNo, 'OS-0009');
    // No note on file stays empty instead of inventing a reason.
    expect(report.page.rows.first.reason, isNull);
  });

  test('discounts keep the line and cart totals apart from the approvals', () {
    final report = DiscountsReport.fromJson(
      _paged(
        totals: {
          'line_discount': '50.00',
          'cart_discount': '30.00',
          'approval_discount': '30.00',
          'approvals': 2,
          'total_discount': '80.00',
        },
        results: [
          {'type': 'LINE', 'transactions': 3, 'total_discount': '50.00'},
          {
            'type': 'APPROVAL',
            'transactions': 2,
            'total_discount': '30.00',
            'approvals': 2,
          },
        ],
      ),
    );

    expect(report.totalLineDiscount, 50.0);
    expect(report.totalCartDiscount, 30.0);
    // APPROVAL is not extra money: the total adds LINE + CART only.
    expect(report.totalDiscount, 80.0);
    expect(report.approvals, 2);
    expect(report.page.rows.last.approvals, 2);
    expect(report.page.rows.first.approvals, isNull);
  });

  test('voids keep the reason on file, empty when nobody wrote one', () {
    final report = VoidsReport.fromJson(
      _paged(
        totals: {'transactions': 2, 'voided_total': '500.00'},
        results: [
          {
            'id': 12,
            'transaction_no': 'OS-0012',
            'date': '2026-10-30T09:30:00+08:00',
            'cashier_id': 4,
            'cashier_name': 'Maria Santos',
            'voided_total': '300.00',
            'reason': 'Wrong item scanned',
          },
          {
            'id': 13,
            'transaction_no': 'OS-0013',
            'date': '2026-10-30T10:30:00+08:00',
            'cashier_id': 4,
            'cashier_name': 'Maria Santos',
            'voided_total': '200.00',
            'reason': '',
          },
        ],
      ),
    );

    expect(report.totalVoided, 500.0);
    expect(report.page.count, 2);
    expect(report.page.rows.first.reason, 'Wrong item scanned');
  });

  /// One viewer run per report id, asserting the report's own row reaches the
  /// shared table instead of the "no endpoint yet" sentence.
  testWidgets('all seven cards open a viewer showing live rows', (
    tester,
  ) async {
    const expected = {
      'item-wise': 'Coke · 1.5L',
      'hourly': '2:00 PM',
      'cashier': 'Maria Santos',
      'bill-wise': 'OS-0009',
      'returns': 'RT-0011',
      'discounts': 'LINE',
      'voids': 'OS-0012',
    };

    for (final entry in expected.entries) {
      await tester.pumpWidget(
        _host(
          ReportViewerView(
            // A fresh key per id, so the viewer reloads instead of reusing the
            // previous report's state.
            key: ValueKey(entry.key),
            report: reportById(entry.key)!,
            repository: _StubSalesDetailRepository(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        // Scoped to the table: the item chart above it names the same item, so
        // the bare text now appears twice.
        find.descendant(
          of: find.byKey(const ValueKey('report-viewer-table')),
          matching: find.text(entry.value),
        ),
        findsOneWidget,
        reason: '${entry.key} draws its API row in the shared table',
      );
      expect(
        find.textContaining('no endpoint yet'),
        findsNothing,
        reason: '${entry.key} has an endpoint now',
      );
    }
  });

  testWidgets('an item with no cost reads as unknown, never as ₱0.00', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ReportViewerView(
          report: reportById('item-wise')!,
          repository: _UncostedItemRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No cost on file'), findsWidgets);
    // A missing cost must not print as a zero-peso cost.
    expect(find.text('₱0.00'), findsNothing);
  });

  testWidgets('a detail report exports its own workbook and keeps PDF off', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ReportViewerView(
          report: reportById('bill-wise')!,
          repository: _StubSalesDetailRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final excel = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Export Excel'),
    );
    expect(
      excel.onPressed,
      isNotNull,
      reason: 'bill-wise owns a workbook builder',
    );
    expect(
      find.byTooltip('Excel lands in P3'),
      findsNothing,
      reason: 'a built workbook never advertises a later phase',
    );

    // Only the sales summary wired the letterhead PDF builder, so this report
    // keeps its PDF button off and says when it lands (decision 01).
    final pdf = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Export PDF'),
    );
    expect(
      pdf.onPressed,
      isNull,
      reason: 'no bill-wise letterhead PDF builder exists yet',
    );
    final pdfTooltip = tester.widget<Tooltip>(
      find.ancestor(
        of: find.text('Export PDF'),
        matching: find.byType(Tooltip),
      ),
    );
    expect(pdfTooltip.message, 'PDF export arrives in P3');
  });

  testWidgets('the summary viewer carries the three KPI tiles and their sums', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ReportViewerView(
          report: reportById('sales-summary')!,
          repository: _StubSalesDetailRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(MetricTile, 'Average bill value'),
      findsOneWidget,
    );
    expect(find.text('Invoice total ÷ bills'), findsOneWidget);
    expect(find.text('₱500.00'), findsWidgets);
    expect(
      find.widgetWithText(MetricTile, 'Average selling price'),
      findsOneWidget,
    );
    expect(find.text('Net ÷ units sold'), findsOneWidget);
    expect(find.widgetWithText(MetricTile, 'Markdown'), findsOneWidget);
    expect(find.text('Discounts ÷ gross'), findsOneWidget);
  });
}
