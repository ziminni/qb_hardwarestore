import 'package:client/data/models/reports.dart';
import 'package:client/features/admin/reports_excel_export.dart';
import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('buildSalesReportXlsx writes Profit Breakdown, Daily Sales, and By Category sheets', () {
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
  });

  test('buildValuationReportXlsx writes By Category and By Location sheets', () {
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
  });
}
