import 'dart:typed_data';

import 'package:client/data/models/reports.dart';
import 'package:client/features/admin/reports_excel_export.dart';
import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every text cell of a sheet, so a test can name what the workbook says
/// without caring which row it sits on.
List<String> _sheetText(Sheet sheet) => [
  for (final row in sheet.rows)
    for (final cell in row) cell?.value?.toString() ?? '',
];

/// Whether any cell of [cells] carries [needle] inside it.
bool _mentions(List<String> cells, String needle) =>
    cells.any((cell) => cell.contains(needle));

/// A page of [rows] out of [count] the server holds; [count] larger than the
/// page is the paged report's truncation.
ReportPage<T> _page<T>(List<T> rows, {int? count}) =>
    ReportPage<T>(count: count ?? rows.length, rows: rows);

SalesByItemReport _salesByItem({double? cogs = 60, int count = 1}) =>
    SalesByItemReport(
      from: '2026-10-01',
      to: '2026-10-30',
      variantCount: 1,
      totalQtyBase: 2,
      totalNet: 95,
      totalCogs: cogs == null ? null : 60,
      totalGrossProfit: cogs == null ? null : 35,
      missingCostDeductions: cogs == null ? 1 : 0,
      page: _page([
        ItemSalesRow(
          sku: 'SKU-007',
          product: 'Cement',
          variant: '40kg',
          uom: 'BAG',
          qtyBase: 2,
          gross: 100,
          discounts: 5,
          net: 95,
          cogs: cogs,
          grossProfit: cogs == null ? null : 35,
          missingCostDeductions: cogs == null ? 1 : 0,
        ),
      ], count: count),
    );

SalesByHour _salesByHour({int count = 1}) => SalesByHour(
  from: '2026-10-01',
  to: '2026-10-30',
  totalTransactions: 2,
  totalInvoice: 224,
  page: _page([
    const HourlySalesRow(hour: 14, transactions: 2, invoiceTotal: 224),
  ], count: count),
);

SalesByCashier _salesByCashier({int count = 1}) => SalesByCashier(
  from: '2026-10-01',
  to: '2026-10-30',
  totalTransactions: 3,
  totalInvoice: 1500,
  totalDiscounts: 50,
  page: _page([
    const CashierSalesRow(
      cashierName: 'Ana Cruz',
      username: 'ana',
      transactions: 3,
      invoiceTotal: 1500,
      discounts: 50,
    ),
  ], count: count),
);

BillWiseReport _billWise({int count = 1}) => BillWiseReport(
  from: '2026-10-01',
  to: '2026-10-30',
  totalTransactions: 1,
  totalDiscount: 0,
  totalGrand: 1500,
  totalMethods: const {'CASH': 1400, 'GCASH': 100},
  page: _page([
    const BillWiseRow(
      id: 1,
      transactionNo: 'BILL-000123',
      orNumber: '0000123',
      invoiceNo: 'INV-0007',
      date: '2026-10-29T14:14:00+08:00',
      cashierName: 'Ana Cruz',
      methods: {'CASH': 1400, 'GCASH': 100},
      discount: 0,
      grandTotal: 1500,
    ),
  ], count: count),
);

ReturnsExchangesReport _returns({int count = 1}) => ReturnsExchangesReport(
  from: '2026-10-01',
  to: '2026-10-30',
  totalTransactions: 1,
  totalReturns: 1,
  totalExchanges: 0,
  totalRefunded: 224,
  page: _page([
    const ReversalRow(
      transactionNo: 'RET-000001',
      date: '2026-10-29T15:00:00+08:00',
      source: 'RETURN',
      cashierName: 'Ana Cruz',
      originalTransactionNo: 'BILL-000123',
      refunded: 224,
      grandTotal: -224,
      reason: 'Wrong size',
    ),
  ], count: count),
);

DiscountsReport _discounts({int count = 1}) => DiscountsReport(
  from: '2026-10-01',
  to: '2026-10-30',
  totalLineDiscount: 30,
  totalCartDiscount: 20,
  totalApprovalDiscount: 20,
  approvals: 1,
  totalDiscount: 50,
  page: _page([
    const DiscountTypeRow(
      type: 'LINE',
      transactions: 2,
      totalDiscount: 30,
      approvals: null,
    ),
    const DiscountTypeRow(
      type: 'APPROVAL',
      transactions: 1,
      totalDiscount: 20,
      approvals: 1,
    ),
  ], count: count),
);

VoidsReport _voids({String? reason = 'Rang twice', int count = 1}) =>
    VoidsReport(
      from: '2026-10-01',
      to: '2026-10-30',
      totalTransactions: 1,
      totalVoided: 500,
      page: _page([
        VoidRow(
          transactionNo: 'BILL-000124',
          date: '2026-10-29T16:00:00+08:00',
          cashierName: 'Ana Cruz',
          voidedTotal: 500,
          reason: reason,
        ),
      ], count: count),
    );

/// The seven sales detail workbooks, each with the title and the detail sheet
/// name its reader sees.
typedef _DetailWorkbook = ({String title, String sheet, Uint8List bytes});

List<_DetailWorkbook> _salesDetailWorkbooks() => [
  (
    title: 'Item-wise sales',
    sheet: 'Items',
    bytes: buildSalesByItemReportXlsx(_salesByItem()),
  ),
  (
    title: 'Hourly sales',
    sheet: 'Hours',
    bytes: buildSalesByHourReportXlsx(_salesByHour()),
  ),
  (
    title: 'Cashier performance',
    sheet: 'Cashiers',
    bytes: buildSalesByCashierReportXlsx(_salesByCashier()),
  ),
  (
    title: 'Bill-wise sales',
    sheet: 'Bills',
    bytes: buildBillWiseReportXlsx(_billWise()),
  ),
  (
    title: 'Returns & exchanges',
    sheet: 'Reversals',
    bytes: buildReturnsExchangesReportXlsx(_returns()),
  ),
  (
    title: 'Discounts',
    sheet: 'Discount types',
    bytes: buildDiscountsReportXlsx(_discounts()),
  ),
  (title: 'Voids', sheet: 'Voids', bytes: buildVoidsReportXlsx(_voids())),
];

void main() {
  test(
    'buildSalesReportXlsx writes Profit Breakdown, Daily Sales, and By Category sheets',
    () {
      const summary = SalesSummary(
        from: '2026-11-01',
        to: '2026-11-21',
        totalTransactions: 2,
        totalGross: 619,
        totalVatableSales: 539.29,
        totalVat: 64.71,
        totalDiscounts: 56,
        totalPaymentFees: 15,
        totalDeliveryFees: 100,
        merchandiseGross: 560,
        merchandiseNetExVat: 450,
        totalCogs: 360,
        grossProfit: 90,
        grossMarginPercent: 20,
        effectiveMarkupPercent: 25,
        costCoverage: CostCoverage(
          costedDeductions: 2,
          missingCostDeductions: 0,
          complete: true,
        ),
        days: [
          SalesDay(
            day: '2026-11-21',
            transactions: 2,
            gross: 619,
            vat: 64.71,
            discounts: 56,
            paymentFees: 15,
            deliveryFees: 100,
            merchandiseNetExVat: 450,
            cogs: 360,
            grossProfit: 90,
          ),
        ],
        categories: [
          SalesCategoryBreakdown(
            categoryId: 1,
            categoryName: 'Cement',
            grossMerchandise: 560,
            discounts: 56,
            netMerchandise: 504,
            cogs: 360,
          ),
        ],
      );

      final bytes = buildSalesReportXlsx(summary);
      final decoded = Excel.decodeBytes(bytes);

      expect(
        decoded.tables.keys,
        containsAll(['Profit Breakdown', 'Daily Sales', 'By Category']),
      );
      final breakdown = decoded.tables['Profit Breakdown']!;
      final textCells = [
        for (final row in breakdown.rows)
          for (final cell in row) cell?.value?.toString() ?? '',
      ];
      expect(textCells, contains('Operational gross profit'));
      expect(textCells, contains('90'));
      expect(textCells, contains('360'));
    },
  );

  test(
    'buildValuationReportXlsx writes By Category and By Location sheets',
    () {
      const valuation = InventoryValuation(
        batchCount: 3,
        totalUnits: 120,
        totalCost: 18000,
        totalRetail: 26000,
        categories: [
          ValuationCategory(
            id: 1,
            name: 'Cement',
            batchCount: 3,
            units: 120,
            cost: 18000,
            retail: 26000,
          ),
        ],
        locations: [
          ValuationLocation(
            locationId: 1,
            locationName: 'Bodega',
            batchCount: 2,
            units: 80,
            cost: 12000,
            retail: 17000,
          ),
        ],
      );

      final bytes = buildValuationReportXlsx(valuation);
      final decoded = Excel.decodeBytes(bytes);

      expect(decoded.tables.keys, containsAll(['By Category', 'By Location']));
      // The location sheet ends in a total, like the category sheet.
      final last = decoded.tables['By Location']!.rows.last;
      expect(last.first?.value.toString(), 'Total');
      expect(last[3]?.value.toString(), anyOf('12000', '12000.0'));
    },
  );

  test('buildVatReportXlsx writes VAT Summary and By Period sheets', () {
    const report = VatReportSummary(
      from: '2026-11-01',
      to: '2026-11-22',
      granularity: 'month',
      totals: OrVatSplit(
        orBacked: VatBucketTotals(
          transactions: 2,
          grossSales: 224,
          vatableSales: 200,
          vat: 24,
        ),
        untaggedOs: VatBucketTotals(
          transactions: 5,
          grossSales: 560,
          vatableSales: 500,
          vat: 60,
        ),
        combined: VatBucketTotals(
          transactions: 7,
          grossSales: 784,
          vatableSales: 700,
          vat: 84,
        ),
      ),
      periods: [
        VatPeriodRow(
          period: '2026-11',
          transactions: 7,
          grossSales: 784,
          vat: 84,
          orBackedTransactions: 2,
          orBackedSales: 224,
          orBackedVatable: 200,
          orBackedVat: 24,
          untaggedTransactions: 5,
          untaggedSales: 560,
          untaggedVatable: 500,
          untaggedVat: 60,
        ),
      ],
    );

    final bytes = buildVatReportXlsx(report);
    final decoded = Excel.decodeBytes(bytes);

    expect(decoded.tables.keys, containsAll(['VAT Summary', 'By Period']));
    final summary = decoded.tables['VAT Summary']!;
    final cells = [
      for (final row in summary.rows)
        for (final cell in row) cell?.value?.toString() ?? '',
    ];
    expect(cells, contains('OR-Tagged Only (Official Receipt)'));
    expect(cells, contains('24'));
    expect(cells, contains('84'));
  });

  group('the seven sales detail workbooks', () {
    test(
      'each opens with a Summary sheet naming the report, then its table',
      () {
        final workbooks = _salesDetailWorkbooks();
        expect(workbooks, hasLength(7));

        for (final workbook in workbooks) {
          final decoded = Excel.decodeBytes(workbook.bytes);
          expect(
            decoded.tables.keys.first,
            'Summary',
            reason: '${workbook.title} opens on its summary',
          );
          expect(
            decoded.tables.keys,
            contains(workbook.sheet),
            reason: workbook.title,
          );
          // The same identity the viewer and the letterhead PDF print.
          final summary = _sheetText(decoded.tables['Summary']!);
          expect(summary, contains(workbook.title));
          expect(summary, contains('2026-10-01 to 2026-10-30'));
          expect(
            _mentions(summary, 'Date range 2026-10-01 to 2026-10-30'),
            isTrue,
            reason: '${workbook.title} names the filters it was cut with',
          );
          expect(
            _mentions(summary, 'PHP'),
            isTrue,
            reason: '${workbook.title} names the money unit',
          );
        }
      },
    );

    test('money and totals stay numeric cells, ids stay text', () {
      final decoded = Excel.decodeBytes(buildBillWiseReportXlsx(_billWise()));
      final bills = decoded.tables['Bills']!;
      final row = bills.rows[1];

      // OR numbers and transaction numbers carry leading zeros: text, or Excel
      // eats them.
      expect(row[0]?.value, isA<TextCellValue>());
      expect(row[1]?.value?.toString(), '0000123');
      // Money is a number, so the reader can sum the column.
      expect(row[6]?.value, isNot(isA<TextCellValue>()));
      expect(row[6]?.value?.toString(), '1500');
      // One column per tender method, per bill.
      expect(row[7]?.value?.toString(), '1400');
      expect(row[8]?.value?.toString(), '100');
    });

    test('a page shorter than the range adds a Notice sheet saying so', () {
      final truncated = Excel.decodeBytes(
        buildVoidsReportXlsx(_voids(count: 120)),
      );
      expect(truncated.tables.keys, contains('Notice'));
      final notice = _sheetText(truncated.tables['Notice']!);
      expect(_mentions(notice, '1 of 120'), isTrue);
      expect(_mentions(notice, 'Narrow the date range'), isTrue);

      // A page that IS the whole range says nothing: no Notice sheet at all.
      final whole = Excel.decodeBytes(buildVoidsReportXlsx(_voids()));
      expect(whole.tables.keys, isNot(contains('Notice')));
    });

    test('a reason starting with = is written as text, never as a formula', () {
      final decoded = Excel.decodeBytes(
        buildVoidsReportXlsx(_voids(reason: '=HYPERLINK("http://x")')),
      );
      expect(
        _sheetText(decoded.tables['Voids']!),
        contains("'=HYPERLINK(\"http://x\")"),
      );
    });

    test('an item with no cost snapshot says so instead of writing zero', () {
      final decoded = Excel.decodeBytes(
        buildSalesByItemReportXlsx(_salesByItem(cogs: null)),
      );
      final text = _sheetText(decoded.tables['Items']!);
      expect(text, contains('No cost on file'));
      expect(text, isNot(contains('0.0')));
    });
  });
}
