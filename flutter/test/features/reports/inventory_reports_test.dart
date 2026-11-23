// Reports suite P2: the ten inventory detail reports behind the shared viewer —
// GRN, STN, batch age, shrinkage, adjustments, reorder, dead stock, fast/slow,
// cycle count and expiry.
//
// Every one of them answers with the SAME `_paged()` envelope the P1 sales
// reports use: `totals` sits outside the 50-row page, so the report's own
// numbers survive paging. The rule that shapes both the models and the screen is
// the inventory one: a quantity with no batch history has NO cost, so its pesos
// read as unknown ("No cost on file"), never as ₱0.00 — a zero would be a claim
// about money that nobody made.

import 'dart:typed_data';

import 'package:client/core/constants/app_areas.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/features/admin/reports_excel_export.dart';
import 'package:client/features/reports/report_catalogue.dart';
import 'package:client/features/reports/report_viewer_page.dart';
import 'package:client/features/reports/reports_catalogue_page.dart';
import 'package:excel_community/excel_community.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The ten P2 inventory report ids, as the catalogue names them.
const List<String> _p2Ids = [
  'grn',
  'stn',
  'batch-age',
  'shrinkage',
  'adjustments',
  'reorder',
  'dead-stock',
  'fast-slow',
  'cycle-count',
  'expiry',
];

/// A `_paged()` body: the payload the server puts OUTSIDE the page, plus the
/// page itself.
Map<String, dynamic> _paged({
  Map<String, dynamic> payload = const {
    'from': '2026-10-01',
    'to': '2026-10-30',
  },
  required Map<String, dynamic> totals,
  required List<Map<String, dynamic>> results,
}) => {
  ...payload,
  'totals': totals,
  'count': results.length,
  'next': null,
  'previous': null,
  'results': results,
};

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

// ---------------------------------------------------------------------------
// The canned pages the stub repository hands the viewer.
// ---------------------------------------------------------------------------

GrnReport _grn() => GrnReport.fromJson(
  _paged(
    totals: {
      'receipts': 1,
      'items': 2,
      'qty': '20.00',
      'billed': 0,
      'unbilled': 1,
      'bill_total': '0.00',
    },
    results: [
      {
        'id': 11,
        'date': '2026-10-29',
        'supplier_id': 3,
        'supplier': 'Holcim Depot',
        'delivery_receipt_no': 'SI-0042',
        'items': 2,
        'qty': '20.00',
        'bill_id': null,
        'bill_total': null,
        'bill_status': null,
      },
    ],
  ),
);

StnReport _stn() => StnReport.fromJson(
  _paged(
    totals: {'transfers': 1, 'lines': 1, 'qty': '4.00'},
    results: [
      {
        'id': 7,
        'number': 'ST-0007',
        'date': '2026-10-29T14:14:00+08:00',
        'from_location': 1,
        'from_location_name': 'Warehouse',
        'to_location': 2,
        'to_location_name': 'Store Floor',
        'lines': 1,
        'qty': '4.00',
        'status': 'COMPLETED',
      },
    ],
  ),
);

BatchAgeReport _batchAge() => BatchAgeReport.fromJson(
  _paged(
    payload: {'as_of': '2026-11-20'},
    totals: {
      'variants': 1,
      'qty_0_30': '6.00',
      'qty_30_90': '4.00',
      'qty_90_plus': '2.00',
      'total_qty': '12.00',
    },
    results: [
      {
        'variant_id': 5,
        'sku': 'CEM-40',
        'product': 'Cement',
        'variant': '40kg',
        'uom': 'BAG',
        'oldest_batch_age_days': 120,
        'qty_0_30': '6.00',
        'qty_30_90': '4.00',
        'qty_90_plus': '2.00',
        'total_qty': '12.00',
      },
    ],
  ),
);

/// A shrinkage day whose two losses had no cost on file: `value` is null, not 0.
ShrinkageReport _shrinkage({bool costed = true}) => ShrinkageReport.fromJson(
  _paged(
    totals: {
      'qty': '3.00',
      'value': costed ? '150.00' : null,
      'missing_cost_lines': costed ? 0 : 2,
      'adjustments': 2,
      'opening_qty': '100.00',
      'received_qty': '20.00',
      'shrinkage_percent': costed ? '2.50' : null,
    },
    results: [
      {
        'date': '2026-10-29',
        'qty': '3.00',
        'value': costed ? '150.00' : null,
        'adjustments': 2,
      },
    ],
  ),
);

AdjustmentsReport _adjustments({bool costed = true}) =>
    AdjustmentsReport.fromJson(
      _paged(
        totals: {
          'adjustments': 1,
          'qty': '-2.00',
          'value': costed ? '-90.00' : null,
          'missing_cost_lines': costed ? 0 : 1,
        },
        results: [
          {
            'id': 31,
            'date': '2026-10-29T09:05:00+08:00',
            'type': 'CORRECTION',
            'product': 'Cement',
            'variant': '40kg',
            'location': 2,
            'location_name': 'Store Floor',
            'user': 'Ana Cruz',
            'qty': '-2.00',
            'value': costed ? '-90.00' : null,
          },
        ],
      ),
    );

ReorderReport _reorder() => ReorderReport.fromJson(
  _paged(
    payload: const {},
    totals: {
      'variants': 1,
      'on_hand': '2.00',
      'threshold': '10.00',
      'gap': '8.00',
    },
    results: [
      {
        'variant_id': 5,
        'sku': 'CEM-40',
        'product': 'Cement',
        'variant': '40kg',
        'uom': 'BAG',
        'on_hand': '2.00',
        'threshold': '10.00',
        'gap': '8.00',
        'locations': [
          {'location': 2, 'location_name': 'Store Floor', 'qty': '2.00'},
        ],
      },
    ],
  ),
);

DeadStockReport _deadStock() => DeadStockReport.fromJson(
  _paged(
    payload: {
      'as_of': '2026-11-20',
      'days': 90,
      'from': '2026-08-22',
      'to': '2026-11-20',
    },
    totals: {'variants': 1, 'on_hand': '5.00', 'landed_value': '750.00'},
    results: [
      {
        'variant_id': 5,
        'sku': 'CEM-40',
        'product': 'Cement',
        'variant': '40kg',
        'uom': 'BAG',
        'on_hand': '5.00',
        'days_since_last_sale': null,
        'landed_value': '750.00',
      },
    ],
  ),
);

FastSlowReport _fastSlow() => FastSlowReport.fromJson(
  _paged(
    totals: {
      'skus_sold': 2,
      'fast': 1,
      'slow': 1,
      'qty_base': '9.00',
      'net_merchandise': '900.00',
    },
    results: [
      {
        'variant_id': 5,
        'sku': 'CEM-40',
        'product': 'Cement',
        'variant': '40kg',
        'uom': 'BAG',
        'band': 'FAST',
        'qty_base': '6.00',
        'net_merchandise': '600.00',
      },
    ],
  ),
);

CycleCountReport _cycleCount({bool costed = true}) => CycleCountReport.fromJson(
  _paged(
    totals: {
      'adjustments': 1,
      'qty': '-2.00',
      'value': costed ? '-90.00' : null,
      'missing_cost_lines': costed ? 0 : 1,
      'on_hand_qty': '10.00',
      'shrinkage_percent': costed ? '16.67' : null,
    },
    results: [
      {
        'id': 41,
        'date': '2026-10-29T18:00:00+08:00',
        'product': 'Cement',
        'variant': '40kg',
        'location': 2,
        'location_name': 'Store Floor',
        'user': 'Ana Cruz',
        'qty': '-2.00',
        'value': costed ? '-90.00' : null,
      },
    ],
  ),
);

ExpiryReport _expiry() => ExpiryReport.fromJson(
  _paged(
    payload: {'as_of': '2026-11-20', 'days': 30},
    totals: {
      'rows': 1,
      'qty': '2.00',
      'value': '300.00',
      'value_expired': '300.00',
      'value_0_30': '0.00',
      'value_31_60': '0.00',
      'value_61_90': '0.00',
      'near_expiry_value': '300.00',
      'on_hand_value': '3000.00',
      'near_expiry_pct': '10.00',
    },
    results: [
      {
        'batch_id': 9,
        'variant_id': 5,
        'sku': 'CEM-40',
        'product': 'Cement',
        'variant': '40kg',
        'uom': 'BAG',
        'location': 'Store Floor',
        'qty': '2.00',
        'value': '300.00',
        'expires_on': '2026-11-15',
        'days_left': -5,
        'bucket': 'expired',
      },
    ],
  ),
);

/// Answers all ten inventory reports off the canned pages above, so the viewer
/// renders real rows without a server.
class _StubInventoryRepository extends ReportsRepository {
  _StubInventoryRepository({this.uncosted = false});

  /// Serves the loss corrections with no cost on file, for the null-cost test.
  final bool uncosted;

  @override
  Future<GrnReport> fetchGrn({String? from, String? to}) async => _grn();

  @override
  Future<StnReport> fetchStn({String? from, String? to}) async => _stn();

  @override
  Future<BatchAgeReport> fetchBatchAge() async => _batchAge();

  @override
  Future<ShrinkageReport> fetchShrinkage({String? from, String? to}) async =>
      _shrinkage(costed: !uncosted);

  @override
  Future<AdjustmentsReport> fetchAdjustments({
    String? from,
    String? to,
  }) async => _adjustments(costed: !uncosted);

  @override
  Future<ReorderReport> fetchReorder() async => _reorder();

  @override
  Future<DeadStockReport> fetchDeadStock() async => _deadStock();

  @override
  Future<FastSlowReport> fetchFastSlow({String? from, String? to}) async =>
      _fastSlow();

  @override
  Future<CycleCountReport> fetchCycleCount({String? from, String? to}) async =>
      _cycleCount(costed: !uncosted);

  @override
  Future<ExpiryReport> fetchExpiry() async => _expiry();
}

/// Every text cell of a sheet, so a test can name what the workbook says.
List<String> _sheetText(Sheet sheet) => [
  for (final row in sheet.rows)
    for (final cell in row) cell?.value?.toString() ?? '',
];

/// One P2 workbook, with the Summary title and the detail sheet it must carry.
typedef _Workbook = ({String title, String sheet, Uint8List bytes});

List<_Workbook> _workbooks() => [
  (
    title: 'Goods received',
    sheet: 'Receipts',
    bytes: buildGrnReportXlsx(_grn()),
  ),
  (
    title: 'Stock transfers',
    sheet: 'Transfers',
    bytes: buildStnReportXlsx(_stn()),
  ),
  (
    title: 'Batch age',
    sheet: 'Batch age',
    bytes: buildBatchAgeReportXlsx(_batchAge()),
  ),
  (
    title: 'Shrinkage & damage',
    sheet: 'Shrinkage',
    bytes: buildShrinkageReportXlsx(_shrinkage()),
  ),
  (
    title: 'Stock adjustments',
    sheet: 'Adjustments',
    bytes: buildAdjustmentsReportXlsx(_adjustments()),
  ),
  (
    title: 'Reorder list',
    sheet: 'Reorder',
    bytes: buildReorderReportXlsx(_reorder()),
  ),
  (
    title: 'Dead stock',
    sheet: 'Dead stock',
    bytes: buildDeadStockReportXlsx(_deadStock()),
  ),
  (
    title: 'Fast & slow movers',
    sheet: 'Movers',
    bytes: buildFastSlowReportXlsx(_fastSlow()),
  ),
  (
    title: 'Cycle count',
    sheet: 'Cycle count',
    bytes: buildCycleCountReportXlsx(_cycleCount()),
  ),
  (title: 'Expiry', sheet: 'Expiry', bytes: buildExpiryReportXlsx(_expiry())),
];

void main() {
  group('P2 inventory models', () {
    test('a goods receipt that was never billed keeps its value unknown', () {
      final report = _grn();

      expect(report.receipts, 1);
      expect(report.billed, 0);
      expect(report.unbilled, 1);
      expect(report.page.rows.single.deliveryReceiptNo, 'SI-0042');
      expect(
        report.page.rows.single.billTotal,
        isNull,
        reason: 'no bill was raised, so there is no peso value to show',
      );
      expect(report.page.rows.single.billStatus, isNull);
    });

    test('a loss day with no cost on file drops to null, never zero', () {
      final report = _shrinkage(costed: false);

      expect(report.qty, 3);
      expect(report.totalValue, isNull);
      expect(report.page.rows.single.value, isNull);
      expect(report.missingCostLines, 2);
      expect(
        report.shrinkagePercent,
        isNull,
        reason: 'no opening stock means no share to report, not a fake 0%',
      );
    });

    test('adjustments and cycle count keep uncosted variance unknown', () {
      final adjust = _adjustments(costed: false);
      expect(
        adjust.page.rows.single.qty,
        -2,
        reason: 'signed: a return lowers',
      );
      expect(adjust.page.rows.single.value, isNull);
      expect(adjust.totalValue, isNull);
      expect(adjust.missingCostLines, 1);

      final count = _cycleCount(costed: false);
      expect(count.page.rows.single.value, isNull);
      expect(count.totalValue, isNull);
      expect(count.shrinkagePercent, isNull);
      expect(count.onHandQty, 10);
    });

    test('the remaining six read their totals outside the page', () {
      expect(_stn().transfers, 1);
      expect(_stn().qty, 4);
      expect(_batchAge().asOf, '2026-11-20');
      expect(_batchAge().page.rows.single.oldestAgeDays, 120);
      expect(_batchAge().qty90plus, 2);
      expect(_reorder().gap, 8);
      expect(
        _reorder().page.rows.single.locations.single.locationName,
        'Store Floor',
      );
      expect(_deadStock().days, 90);
      expect(
        _deadStock().page.rows.single.daysSinceLastSale,
        isNull,
        reason: 'never sold is a different fact from sold long ago',
      );
      expect(_fastSlow().page.rows.single.band, 'FAST');
      expect(_fastSlow().skusSold, 2);
      expect(_expiry().page.rows.single.daysLeft, -5);
      expect(_expiry().page.rows.single.bucket, 'expired');
      expect(_expiry().nearExpiryPct, 10);
    });
  });

  group('P2 catalogue', () {
    test('every P2 card is live and its id reaches a viewer', () {
      final live = reportById('grn');

      expect(live, isNotNull, reason: 'the GRN endpoint exists server-side');
      for (final id in _p2Ids) {
        final report = reportById(id);
        expect(report, isNotNull, reason: '$id has no catalogue card');
        expect(report!.available, isTrue, reason: '$id has a live endpoint');
        expect(report.section, ReportSection.inventory);
      }
    });

    testWidgets('the stocker sees the ten inventory cards and no Sales', (
      tester,
    ) async {
      final opened = <String>[];
      await tester.pumpWidget(
        _host(
          ReportsCatalogueView(areas: {AppAreas.inventory}, onOpen: opened.add),
        ),
      );

      expect(find.text('INVENTORY'), findsOneWidget);
      expect(find.text('Inventory valuation'), findsOneWidget);
      for (final id in _p2Ids) {
        expect(
          find.text(reportById(id)!.title),
          findsOneWidget,
          reason: '$id is the stocker\'s own shelf work',
        );
      }
      expect(find.text('SALES'), findsNothing);
      expect(
        find.text('P1'),
        findsNothing,
        reason: 'no live card carries a tag',
      );

      await tester.tap(find.text('Reorder list'));
      await tester.pumpAndSettle();
      expect(opened, ['reorder']);
    });
  });

  group('P2 viewer', () {
    /// What each report's table must say once its page arrives.
    const marker = {
      'grn': 'SI-0042',
      'stn': 'ST-0007',
      'batch-age': 'Cement · 40kg',
      'shrinkage': 'Oct 29, 2026',
      'adjustments': 'Ana Cruz',
      'reorder': 'Cement · 40kg',
      'dead-stock': 'Never sold',
      'fast-slow': 'FAST',
      'cycle-count': 'Ana Cruz',
      'expiry': 'Expired 5 days ago',
    };

    testWidgets('each report draws its page and offers its workbook', (
      tester,
    ) async {
      for (final id in _p2Ids) {
        await tester.pumpWidget(
          _host(
            ReportViewerView(
              key: ValueKey(id),
              report: reportById(id)!,
              repository: _StubInventoryRepository(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Scoped to the table: the chart above it repeats the same label, and
        // this assertion is about the row the API sent.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('report-viewer-table')),
            matching: find.text(marker[id]!),
          ),
          findsOneWidget,
          reason: '$id draws its API row in the shared table',
        );
        expect(
          find.textContaining('no endpoint yet'),
          findsNothing,
          reason: '$id has an endpoint now',
        );

        final excel = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Export Excel'),
        );
        expect(excel.onPressed, isNotNull, reason: '$id owns a workbook');
        expect(
          find.byTooltip('Excel lands in P3'),
          findsNothing,
          reason: 'a built workbook never advertises a later phase',
        );

        // PDF stays P3: only the sales summary wired a letterhead builder.
        final pdf = tester.widget<OutlinedButton>(
          find.widgetWithText(OutlinedButton, 'Export PDF'),
        );
        expect(pdf.onPressed, isNull, reason: 'no $id letterhead PDF exists');
        final tooltip = tester.widget<Tooltip>(
          find.ancestor(
            of: find.text('Export PDF'),
            matching: find.byType(Tooltip),
          ),
        );
        expect(tooltip.message, 'PDF export arrives in P3');
      }
    });

    testWidgets('an uncosted loss reads as unknown, never as ₱0.00', (
      tester,
    ) async {
      for (final id in ['shrinkage', 'adjustments', 'cycle-count']) {
        await tester.pumpWidget(
          _host(
            ReportViewerView(
              key: ValueKey(id),
              report: reportById(id)!,
              repository: _StubInventoryRepository(uncosted: true),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('No cost on file'),
          findsWidgets,
          reason: '$id must say the cost is unknown',
        );
        expect(
          find.text('₱0.00'),
          findsNothing,
          reason: '$id must not print a missing cost as zero pesos',
        );
      }
    });
  });

  group('P2 workbooks', () {
    test('each one opens on a Summary and carries its detail sheet', () {
      for (final workbook in _workbooks()) {
        final decoded = Excel.decodeBytes(workbook.bytes);

        expect(
          decoded.tables.keys,
          contains('Summary'),
          reason: workbook.title,
        );
        expect(
          decoded.tables.keys,
          contains(workbook.sheet),
          reason: workbook.title,
        );
        expect(
          _sheetText(decoded.tables['Summary']!),
          contains(workbook.title),
          reason: 'the workbook says what it is when opened alone',
        );
      }
    });

    test('an uncosted loss is written as words, not as zero', () {
      final decoded = Excel.decodeBytes(
        buildShrinkageReportXlsx(_shrinkage(costed: false)),
      );

      expect(
        _sheetText(decoded.tables['Shrinkage']!),
        contains('No cost on file'),
      );
      expect(
        _sheetText(decoded.tables['Summary']!),
        contains('No cost on file'),
      );
    });

    test(
      'a supplier name starting with = is written as text, not a formula',
      () {
        final report = GrnReport.fromJson(
          _paged(
            totals: const {'receipts': 1, 'items': 1, 'qty': '1.00'},
            results: [
              {
                'id': 1,
                'date': '2026-10-29',
                'supplier': '=HYPERLINK("http://x")',
                'delivery_receipt_no': '=1+1',
                'items': 1,
                'qty': '1.00',
                'bill_total': '10.00',
                'bill_status': 'PAID',
              },
            ],
          ),
        );
        final decoded = Excel.decodeBytes(buildGrnReportXlsx(report));

        expect(
          _sheetText(decoded.tables['Receipts']!),
          contains("'=HYPERLINK(\"http://x\")"),
        );
      },
    );
  });
}
