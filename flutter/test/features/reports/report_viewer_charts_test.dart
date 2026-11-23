// The shared report viewer draws graphs, not only tiles and a table: a sales
// trend for the summary, bars per item, bars per cashier, a tender split on
// bill-wise, and one honest chart (or two) for every other report that carries
// something a chart can say. A report with nothing to plot says so in words and
// never throws.
//
// Stub repositories answer like the server does, so the viewer renders real
// numbers without a backend.

import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/features/reports/report_catalogue.dart';
import 'package:client/features/reports/report_viewer_page.dart';
import 'package:client/shared/widgets/analytics_charts.dart';
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

/// Every report the viewer can load, in catalogue order.
const _allChartedIds = [
  'sales-summary',
  'vat-summary',
  'item-wise',
  'hourly',
  'cashier',
  'bill-wise',
  'returns',
  'discounts',
  'voids',
  'inventory-valuation',
  'stock-movements',
  'requisition-history',
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
        batchCount: 2,
        totalUnits: 14,
        totalCost: 400,
        totalRetail: 600,
        categories: [
          ValuationCategory(
            id: 1,
            name: 'Drinks',
            batchCount: 1,
            units: 10,
            cost: 300,
            retail: 450,
          ),
          ValuationCategory(
            id: 2,
            name: 'Snacks',
            batchCount: 1,
            units: 4,
            cost: 100,
            retail: 150,
          ),
        ],
        locations: [
          ValuationLocation(
            locationId: 1,
            locationName: 'Store Floor',
            batchCount: 1,
            units: 10,
            cost: 300,
            retail: 450,
          ),
          ValuationLocation(
            locationId: 2,
            locationName: 'Warehouse',
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

  @override
  Future<SalesByHour> fetchSalesByHour({String? from, String? to}) async =>
      const SalesByHour(
        from: '2026-10-01',
        to: '2026-10-30',
        totalTransactions: 9,
        totalInvoice: 2500,
        page: ReportPage<HourlySalesRow>(
          count: 3,
          rows: [
            HourlySalesRow(hour: 8, transactions: 1, invoiceTotal: 250),
            HourlySalesRow(hour: 12, transactions: 3, invoiceTotal: 1250),
            HourlySalesRow(hour: 18, transactions: 5, invoiceTotal: 1000),
          ],
        ),
      );

  @override
  Future<VatReportSummary> fetchVatSummary({
    String? from,
    String? to,
    String granularity = 'day',
  }) async => const VatReportSummary(
    from: '2026-10-01',
    to: '2026-10-30',
    granularity: 'day',
    totals: OrVatSplit(
      orBacked: VatBucketTotals(
        transactions: 4,
        grossSales: 1200,
        vatableSales: 1071.43,
        vat: 128.57,
      ),
      untaggedOs: VatBucketTotals(
        transactions: 2,
        grossSales: 600,
        vatableSales: 535.71,
        vat: 64.29,
      ),
      combined: VatBucketTotals(
        transactions: 6,
        grossSales: 1800,
        vatableSales: 1607.14,
        vat: 192.86,
      ),
    ),
    periods: [],
  );

  @override
  Future<StockMovements> fetchStockMovements({
    String? from,
    String? to,
  }) async => const StockMovements(
    from: '2026-10-01',
    to: '2026-10-30',
    totalIn: 120,
    totalOut: 18,
    receiptsByDay: [
      MovementDay(date: '2026-10-27', receipts: 1, qtyIn: 40),
      MovementDay(date: '2026-10-28', receipts: 2, qtyIn: 80),
    ],
    adjustmentsByType: [
      MovementType(type: 'DAMAGE', movements: 2, qtyOut: 12),
      MovementType(type: 'THEFT', movements: 1, qtyOut: 6),
    ],
  );

  @override
  Future<RequisitionHistory> fetchRequisitionHistory() async =>
      const RequisitionHistory(
        from: '2026-10-01',
        to: '2026-10-30',
        statusFilter: null,
        countByStatus: {'APPROVED': 2, 'PENDING': 1},
        requisitions: [
          RequisitionHistoryRow(
            id: 1,
            reqNumber: 'REQ-0001',
            status: 'APPROVED',
            project: 'Store Floor',
            requestedBy: 'Maria Santos',
            approvedBy: 'Jose Reyes',
            createdAt: '2026-10-27T09:00:00+08:00',
          ),
        ],
      );

  @override
  Future<ReturnsExchangesReport> fetchReturnsExchanges({
    String? from,
    String? to,
  }) async => const ReturnsExchangesReport(
    from: '2026-10-01',
    to: '2026-10-30',
    totalTransactions: 3,
    totalReturns: 2,
    totalExchanges: 1,
    totalRefunded: 450,
    page: ReportPage<ReversalRow>(
      count: 1,
      rows: [
        ReversalRow(
          transactionNo: 'OS-0007',
          date: '2026-10-28T10:00:00+08:00',
          source: 'RETURN',
          cashierName: 'Maria Santos',
          originalTransactionNo: 'OS-0001',
          refunded: 450,
          grandTotal: -450,
          reason: 'Spoiled',
        ),
      ],
    ),
  );

  @override
  Future<DiscountsReport> fetchDiscounts({String? from, String? to}) async =>
      const DiscountsReport(
        from: '2026-10-01',
        to: '2026-10-30',
        totalLineDiscount: 80,
        totalCartDiscount: 50,
        totalApprovalDiscount: 30,
        approvals: 1,
        totalDiscount: 130,
        page: ReportPage<DiscountTypeRow>(
          count: 2,
          rows: [
            DiscountTypeRow(
              type: 'LINE',
              transactions: 4,
              totalDiscount: 80,
              approvals: null,
            ),
            DiscountTypeRow(
              type: 'CART',
              transactions: 2,
              totalDiscount: 50,
              approvals: 1,
            ),
          ],
        ),
      );

  @override
  Future<VoidsReport> fetchVoids({String? from, String? to}) async =>
      const VoidsReport(
        from: '2026-10-01',
        to: '2026-10-30',
        totalTransactions: 2,
        totalVoided: 300,
        page: ReportPage<VoidRow>(
          count: 2,
          rows: [
            VoidRow(
              transactionNo: 'OS-0008',
              date: '2026-10-28T11:00:00+08:00',
              cashierName: 'Maria Santos',
              voidedTotal: 100,
              reason: 'Wrong item',
            ),
            VoidRow(
              transactionNo: 'OS-0009',
              date: '2026-10-29T12:00:00+08:00',
              cashierName: 'Jose Reyes',
              voidedTotal: 200,
              reason: null,
            ),
          ],
        ),
      );

  @override
  Future<GrnReport> fetchGrn({String? from, String? to}) async =>
      const GrnReport(
        from: '2026-10-01',
        to: '2026-10-30',
        receipts: 2,
        items: 4,
        qty: 60,
        billed: 1,
        unbilled: 1,
        billTotal: 900,
        page: ReportPage<GrnRow>(
          count: 2,
          rows: [
            GrnRow(
              id: 1,
              date: '2026-10-27T09:00:00+08:00',
              supplier: 'San Miguel',
              deliveryReceiptNo: 'DR-0001',
              items: 2,
              qty: 20,
              billTotal: 900,
              billStatus: 'BILLED',
            ),
            GrnRow(
              id: 2,
              date: '2026-10-28T10:00:00+08:00',
              supplier: 'Purefoods',
              deliveryReceiptNo: 'DR-0002',
              items: 2,
              qty: 40,
              billTotal: null,
              billStatus: null,
            ),
          ],
        ),
      );

  @override
  Future<StnReport> fetchStn({String? from, String? to}) async =>
      const StnReport(
        from: '2026-10-01',
        to: '2026-10-30',
        transfers: 2,
        lines: 3,
        qty: 30,
        page: ReportPage<StnRow>(
          count: 2,
          rows: [
            StnRow(
              id: 1,
              number: 'STN-0001',
              date: '2026-10-27T09:00:00+08:00',
              fromLocationName: 'Warehouse',
              toLocationName: 'Store Floor',
              lines: 2,
              qty: 18,
              status: 'COMPLETED',
            ),
            StnRow(
              id: 2,
              number: 'STN-0002',
              date: '2026-10-28T09:00:00+08:00',
              fromLocationName: 'Warehouse',
              toLocationName: 'Store Floor',
              lines: 1,
              qty: 12,
              status: 'COMPLETED',
            ),
          ],
        ),
      );

  @override
  Future<BatchAgeReport> fetchBatchAge() async => const BatchAgeReport(
    asOf: '2026-10-30',
    variants: 2,
    qty0to30: 10,
    qty30to90: 6,
    qty90plus: 4,
    totalQty: 20,
    page: ReportPage<BatchAgeRow>(
      count: 1,
      rows: [
        BatchAgeRow(
          variantId: 1,
          sku: 'COKE-15',
          product: 'Coke',
          variant: '1.5L',
          uom: 'BTL',
          oldestAgeDays: 20,
          qty0to30: 10,
          qty30to90: 6,
          qty90plus: 4,
          totalQty: 20,
        ),
      ],
    ),
  );

  @override
  Future<ShrinkageReport> fetchShrinkage({
    String? from,
    String? to,
  }) async => const ShrinkageReport(
    from: '2026-10-01',
    to: '2026-10-30',
    qty: 12,
    totalValue: 480,
    missingCostLines: 0,
    adjustments: 3,
    openingQty: 200,
    receivedQty: 60,
    shrinkagePercent: 4.6,
    page: ReportPage<ShrinkageRow>(
      count: 2,
      rows: [
        ShrinkageRow(date: '2026-10-27', qty: 8, value: 320, adjustments: 2),
        ShrinkageRow(date: '2026-10-28', qty: 4, value: 160, adjustments: 1),
      ],
    ),
  );

  @override
  Future<AdjustmentsReport> fetchAdjustments({
    String? from,
    String? to,
  }) async => const AdjustmentsReport(
    from: '2026-10-01',
    to: '2026-10-30',
    adjustments: 2,
    qty: 3,
    totalValue: 120,
    missingCostLines: 0,
    page: ReportPage<AdjustmentRow>(
      count: 2,
      rows: [
        AdjustmentRow(
          id: 1,
          date: '2026-10-27',
          type: 'CORRECTION',
          product: 'Coke',
          variant: '1.5L',
          locationName: 'Store Floor',
          userName: 'Maria Santos',
          qty: 5,
          value: 200,
        ),
        AdjustmentRow(
          id: 2,
          date: '2026-10-28',
          type: 'RETURN',
          product: 'Chips',
          variant: '50g',
          locationName: 'Warehouse',
          userName: 'Jose Reyes',
          qty: -2,
          value: -80,
        ),
      ],
    ),
  );

  @override
  Future<ReorderReport> fetchReorder() async => const ReorderReport(
    variants: 2,
    onHand: 9,
    threshold: 20,
    gap: 21,
    page: ReportPage<ReorderRow>(
      count: 2,
      rows: [
        ReorderRow(
          variantId: 1,
          sku: 'COKE-15',
          product: 'Coke',
          variant: '1.5L',
          uom: 'BTL',
          onHand: 3,
          threshold: 12,
          gap: 9,
          locations: [
            ReorderShelf(locationId: 1, locationName: 'Store Floor', qty: 3),
          ],
        ),
        ReorderRow(
          variantId: 2,
          sku: 'CHIPS-50',
          product: 'Chips',
          variant: '50g',
          uom: 'PACK',
          onHand: 6,
          threshold: 12,
          gap: 6,
          locations: [],
        ),
      ],
    ),
  );

  @override
  Future<DeadStockReport> fetchDeadStock() async => const DeadStockReport(
    asOf: '2026-10-30',
    days: 90,
    from: '2026-08-01',
    to: '2026-10-30',
    variants: 2,
    onHand: 7,
    landedValue: 1900,
    page: ReportPage<DeadStockRow>(
      count: 2,
      rows: [
        DeadStockRow(
          variantId: 1,
          sku: 'CEMENT-40',
          product: 'Cement',
          variant: '40kg',
          uom: 'BAG',
          onHand: 5,
          daysSinceLastSale: null,
          landedValue: 1500,
        ),
        DeadStockRow(
          variantId: 2,
          sku: 'PAINT-4L',
          product: 'Paint',
          variant: '4L',
          uom: 'CAN',
          onHand: 2,
          daysSinceLastSale: 120,
          landedValue: 400,
        ),
      ],
    ),
  );

  @override
  Future<FastSlowReport> fetchFastSlow({String? from, String? to}) async =>
      const FastSlowReport(
        from: '2026-10-01',
        to: '2026-10-30',
        skusSold: 4,
        fast: 1,
        slow: 1,
        qtyBase: 40,
        netMerchandise: 3200,
        page: ReportPage<FastSlowRow>(
          count: 2,
          rows: [
            FastSlowRow(
              variantId: 1,
              sku: 'COKE-15',
              product: 'Coke',
              variant: '1.5L',
              uom: 'BTL',
              band: 'FAST',
              qtyBase: 30,
              netMerchandise: 2400,
            ),
            FastSlowRow(
              variantId: 2,
              sku: 'CHIPS-50',
              product: 'Chips',
              variant: '50g',
              uom: 'PACK',
              band: 'SLOW',
              qtyBase: 10,
              netMerchandise: 800,
            ),
          ],
        ),
      );

  @override
  Future<CycleCountReport> fetchCycleCount({String? from, String? to}) async =>
      const CycleCountReport(
        from: '2026-10-01',
        to: '2026-10-30',
        adjustments: 2,
        qty: -3,
        totalValue: 120,
        missingCostLines: 0,
        onHandQty: 80,
        shrinkagePercent: 3.6,
        page: ReportPage<CycleCountRow>(
          count: 2,
          rows: [
            CycleCountRow(
              id: 1,
              date: '2026-10-27',
              product: 'Coke',
              variant: '1.5L',
              locationName: 'Store Floor',
              userName: 'Maria Santos',
              qty: -5,
              value: 200,
            ),
            CycleCountRow(
              id: 2,
              date: '2026-10-28',
              product: 'Chips',
              variant: '50g',
              locationName: 'Warehouse',
              userName: 'Jose Reyes',
              qty: 2,
              value: 80,
            ),
          ],
        ),
      );

  @override
  Future<ExpiryReport> fetchExpiry() async => const ExpiryReport(
    asOf: '2026-10-30',
    days: 90,
    rowCount: 2,
    qty: 12,
    value: 1200,
    valueExpired: 400,
    value0to30: 500,
    value31to60: 200,
    value61to90: 100,
    nearExpiryValue: 800,
    onHandValue: 8000,
    nearExpiryPct: 10,
    page: ReportPage<ExpiryRow>(
      count: 2,
      rows: [
        ExpiryRow(
          batchId: 1,
          variantId: 1,
          sku: 'MILK-1L',
          product: 'Milk',
          variant: '1L',
          uom: 'PACK',
          location: 'Store Floor',
          qty: 4,
          value: 400,
          expiresOn: '2026-10-01',
          daysLeft: -29,
          bucket: 'expired',
        ),
        ExpiryRow(
          batchId: 2,
          variantId: 2,
          sku: 'JUICE-1L',
          product: 'Juice',
          variant: '1L',
          uom: 'PACK',
          location: 'Store Floor',
          qty: 8,
          value: 800,
          expiresOn: '2026-11-15',
          daysLeft: 16,
          bucket: '0-30',
        ),
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

  @override
  Future<SalesByHour> fetchSalesByHour({String? from, String? to}) async =>
      const SalesByHour(
        from: '2026-10-01',
        to: '2026-10-30',
        totalTransactions: 0,
        totalInvoice: 0,
        page: ReportPage<HourlySalesRow>(count: 0, rows: []),
      );

  @override
  Future<VatReportSummary> fetchVatSummary({
    String? from,
    String? to,
    String granularity = 'day',
  }) async => const VatReportSummary(
    from: '2026-10-01',
    to: '2026-10-30',
    granularity: 'day',
    totals: OrVatSplit(),
    periods: [],
  );

  @override
  Future<InventoryValuation> fetchInventoryValuation() async =>
      const InventoryValuation(
        batchCount: 0,
        totalUnits: 0,
        totalCost: 0,
        totalRetail: 0,
        categories: [],
      );

  @override
  Future<StockMovements> fetchStockMovements({
    String? from,
    String? to,
  }) async => const StockMovements(
    from: '2026-10-01',
    to: '2026-10-30',
    totalIn: 0,
    totalOut: 0,
    receiptsByDay: [],
    adjustmentsByType: [],
  );

  @override
  Future<RequisitionHistory> fetchRequisitionHistory() async =>
      const RequisitionHistory(
        from: '2026-10-01',
        to: '2026-10-30',
        statusFilter: null,
        countByStatus: {},
        requisitions: [],
      );

  @override
  Future<ReturnsExchangesReport> fetchReturnsExchanges({
    String? from,
    String? to,
  }) async => const ReturnsExchangesReport(
    from: '2026-10-01',
    to: '2026-10-30',
    totalTransactions: 0,
    totalReturns: 0,
    totalExchanges: 0,
    totalRefunded: 0,
    page: ReportPage<ReversalRow>(count: 0, rows: []),
  );

  @override
  Future<DiscountsReport> fetchDiscounts({String? from, String? to}) async =>
      const DiscountsReport(
        from: '2026-10-01',
        to: '2026-10-30',
        totalLineDiscount: 0,
        totalCartDiscount: 0,
        totalApprovalDiscount: 0,
        approvals: 0,
        totalDiscount: 0,
        page: ReportPage<DiscountTypeRow>(count: 0, rows: []),
      );

  @override
  Future<VoidsReport> fetchVoids({String? from, String? to}) async =>
      const VoidsReport(
        from: '2026-10-01',
        to: '2026-10-30',
        totalTransactions: 0,
        totalVoided: 0,
        page: ReportPage<VoidRow>(count: 0, rows: []),
      );

  @override
  Future<GrnReport> fetchGrn({String? from, String? to}) async =>
      const GrnReport(
        from: '2026-10-01',
        to: '2026-10-30',
        receipts: 0,
        items: 0,
        qty: 0,
        billed: 0,
        unbilled: 0,
        billTotal: 0,
        page: ReportPage<GrnRow>(count: 0, rows: []),
      );

  @override
  Future<StnReport> fetchStn({String? from, String? to}) async =>
      const StnReport(
        from: '2026-10-01',
        to: '2026-10-30',
        transfers: 0,
        lines: 0,
        qty: 0,
        page: ReportPage<StnRow>(count: 0, rows: []),
      );

  @override
  Future<BatchAgeReport> fetchBatchAge() async => const BatchAgeReport(
    asOf: '2026-10-30',
    variants: 0,
    qty0to30: 0,
    qty30to90: 0,
    qty90plus: 0,
    totalQty: 0,
    page: ReportPage<BatchAgeRow>(count: 0, rows: []),
  );

  @override
  Future<ShrinkageReport> fetchShrinkage({String? from, String? to}) async =>
      const ShrinkageReport(
        from: '2026-10-01',
        to: '2026-10-30',
        qty: 0,
        totalValue: null,
        missingCostLines: 0,
        adjustments: 0,
        openingQty: 0,
        receivedQty: 0,
        shrinkagePercent: null,
        page: ReportPage<ShrinkageRow>(count: 0, rows: []),
      );

  @override
  Future<AdjustmentsReport> fetchAdjustments({
    String? from,
    String? to,
  }) async => const AdjustmentsReport(
    from: '2026-10-01',
    to: '2026-10-30',
    adjustments: 0,
    qty: 0,
    totalValue: null,
    missingCostLines: 0,
    page: ReportPage<AdjustmentRow>(count: 0, rows: []),
  );

  @override
  Future<ReorderReport> fetchReorder() async => const ReorderReport(
    variants: 0,
    onHand: 0,
    threshold: 0,
    gap: 0,
    page: ReportPage<ReorderRow>(count: 0, rows: []),
  );

  @override
  Future<DeadStockReport> fetchDeadStock() async => const DeadStockReport(
    asOf: '2026-10-30',
    days: 90,
    from: '2026-08-01',
    to: '2026-10-30',
    variants: 0,
    onHand: 0,
    landedValue: 0,
    page: ReportPage<DeadStockRow>(count: 0, rows: []),
  );

  @override
  Future<FastSlowReport> fetchFastSlow({String? from, String? to}) async =>
      const FastSlowReport(
        from: '2026-10-01',
        to: '2026-10-30',
        skusSold: 0,
        fast: 0,
        slow: 0,
        qtyBase: 0,
        netMerchandise: 0,
        page: ReportPage<FastSlowRow>(count: 0, rows: []),
      );

  @override
  Future<CycleCountReport> fetchCycleCount({String? from, String? to}) async =>
      const CycleCountReport(
        from: '2026-10-01',
        to: '2026-10-30',
        adjustments: 0,
        qty: 0,
        totalValue: null,
        missingCostLines: 0,
        onHandQty: 0,
        shrinkagePercent: null,
        page: ReportPage<CycleCountRow>(count: 0, rows: []),
      );

  @override
  Future<ExpiryReport> fetchExpiry() async => const ExpiryReport(
    asOf: '2026-10-30',
    days: 90,
    rowCount: 0,
    qty: 0,
    value: 0,
    valueExpired: 0,
    value0to30: 0,
    value31to60: 0,
    value61to90: 0,
    nearExpiryValue: 0,
    onHandValue: 0,
    nearExpiryPct: null,
    page: ReportPage<ExpiryRow>(count: 0, rows: []),
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

/// One of the three chart cards the viewer draws.
final _anyChart = find.byWidgetPredicate(
  (widget) =>
      widget is ShareSplitChart ||
      widget is HorizontalComparisonChart ||
      widget is GroupedBarTrendChart,
);

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

    testWidgets('hourly draws a bar per hour of the day', (tester) async {
      await _open(tester, 'hourly', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-hourly-chart')),
        findsOneWidget,
      );
      // Peak hours are labelled as clocks, not as raw 0-23 numbers.
      expect(find.text('12:00 PM'), findsWidgets);
    });

    testWidgets('VAT draws the whole-VAT vs OR-tagged split', (tester) async {
      await _open(tester, 'vat-summary', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-vat-split')),
        findsOneWidget,
      );
      expect(find.text('OR-tagged VAT'), findsWidgets);
      expect(find.text('Untagged VAT'), findsWidgets);
    });

    testWidgets('valuation splits stock value by category and location', (
      tester,
    ) async {
      await _open(tester, 'inventory-valuation', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-valuation-category-split')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('report-viewer-valuation-location-split')),
        findsOneWidget,
      );
      expect(find.text('Warehouse'), findsWidgets);
    });

    testWidgets('stock movements draws daily receipts and reason bars', (
      tester,
    ) async {
      await _open(tester, 'stock-movements', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-movements-chart')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('report-viewer-movement-types-chart')),
        findsOneWidget,
      );
      expect(find.text('DAMAGE'), findsWidgets);
    });

    testWidgets('requisitions draw a count split by status', (tester) async {
      await _open(tester, 'requisition-history', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-requisition-split')),
        findsOneWidget,
      );
      expect(find.text('APPROVED'), findsWidgets);
    });

    testWidgets('returns draw the money-back vs swap split', (tester) async {
      await _open(tester, 'returns', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-returns-split')),
        findsOneWidget,
      );
      expect(find.textContaining('Exchanges'), findsWidgets);
    });

    testWidgets('discounts draw a bar per discount type', (tester) async {
      await _open(tester, 'discounts', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-discounts-chart')),
        findsOneWidget,
      );
      expect(find.text('LINE'), findsWidgets);
    });

    testWidgets('voids draw a bar per reason, blanks named as blanks', (
      tester,
    ) async {
      await _open(tester, 'voids', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-voids-chart')),
        findsOneWidget,
      );
      expect(find.text('Wrong item'), findsWidgets);
      expect(find.text('No reason recorded'), findsWidgets);
    });

    testWidgets('goods received draws units received per delivery day', (
      tester,
    ) async {
      await _open(tester, 'grn', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-grn-chart')),
        findsOneWidget,
      );
    });

    testWidgets('stock transfers draw units moved per day', (tester) async {
      await _open(tester, 'stn', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-stn-chart')),
        findsOneWidget,
      );
    });

    testWidgets('batch age draws its three age buckets', (tester) async {
      await _open(tester, 'batch-age', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-batch-age-chart')),
        findsOneWidget,
      );
      expect(find.text('90+ days'), findsWidgets);
    });

    testWidgets('shrinkage draws the daily loss', (tester) async {
      await _open(tester, 'shrinkage', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-shrinkage-chart')),
        findsOneWidget,
      );
    });

    testWidgets('adjustments split corrections against returns', (
      tester,
    ) async {
      await _open(tester, 'adjustments', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-adjustments-split')),
        findsOneWidget,
      );
      expect(find.textContaining('CORRECTION'), findsWidgets);
    });

    testWidgets('reorder draws the biggest shortfalls first', (tester) async {
      await _open(tester, 'reorder', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-reorder-chart')),
        findsOneWidget,
      );
    });

    testWidgets('dead stock draws the idle money per item', (tester) async {
      await _open(tester, 'dead-stock', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-dead-stock-chart')),
        findsOneWidget,
      );
    });

    testWidgets('fast & slow movers split units by band', (tester) async {
      await _open(tester, 'fast-slow', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-fast-slow-split')),
        findsOneWidget,
      );
      expect(find.textContaining('Slow movers'), findsWidgets);
    });

    testWidgets('cycle count splits counted-more against counted-short', (
      tester,
    ) async {
      await _open(tester, 'cycle-count', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-cycle-count-split')),
        findsOneWidget,
      );
    });

    testWidgets('expiry draws its 30/60/90/expired buckets', (tester) async {
      await _open(tester, 'expiry', _StubChartRepository());

      expect(
        find.byKey(const ValueKey('report-viewer-expiry-chart')),
        findsOneWidget,
      );
      expect(find.text('Already expired'), findsWidgets);
    });

    testWidgets('every report that loads draws at least one chart', (
      tester,
    ) async {
      for (final id in _allChartedIds) {
        await _open(tester, id, _StubChartRepository());

        expect(
          find.text('No data for this range'),
          findsNothing,
          reason: '$id has numbers to plot',
        );
        expect(_anyChart, findsWidgets, reason: '$id draws a chart');
        expect(
          find.byKey(const ValueKey('report-viewer-table')),
          findsOneWidget,
          reason: '$id still lists its rows',
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('a range with nothing to plot says so instead of throwing', (
      tester,
    ) async {
      for (final id in _allChartedIds) {
        await _open(tester, id, _EmptyChartRepository());

        expect(
          find.text('No data for this range'),
          findsOneWidget,
          reason: '$id has an empty range',
        );
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('a plan-only KPI card plots nothing and loads no endpoint', (
      tester,
    ) async {
      await _open(tester, 'abv', _StubChartRepository());

      // The card is disabled in the catalogue: no endpoint, no tiles, no chart.
      expect(_anyChart, findsNothing);
      expect(find.text('No data for this range'), findsNothing);
      expect(find.byKey(const ValueKey('report-viewer-table')), findsNothing);
    });
  });
}
