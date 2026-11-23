import 'package:client/data/models/json_field.dart';

/// Server-driven aggregates behind the admin Reports screen (decision 16).
///
/// Shapes verified against `backend_django/apps/reports/views.py`. Every SUM the
/// server computes is nullable over an empty range, so sums parse through
/// [optionalDecimalField] — "no sales" must read as zero, not a parse crash.
/// COUNTs never null, so those stay strict.

/// Reads an aggregate decimal: null or missing means zero (an empty SUM), but a
/// present garbage value still throws — zero must mean "nothing", never "broken".
double optionalDecimalField(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return 0.0;
  if (value is num) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed == null) {
      throw FormatException('Field "$key" is not a decimal: "$value"');
    }
    return parsed;
  }
  throw FormatException(
    'Field "$key" has unsupported type ${value.runtimeType}',
  );
}

/// Reads a nullable aggregate decimal: null or missing stays null (for example
/// when cost history is missing and must not be fabricated as ₱0.00).
double? nullableDecimalField(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed == null) {
      throw FormatException('Field "$key" is not a decimal: "$value"');
    }
    return parsed;
  }
  throw FormatException(
    'Field "$key" has unsupported type ${value.runtimeType}',
  );
}

/// How many stock deductions in a sales period carry a snapshotted landed cost.
class CostCoverage {
  const CostCoverage({
    this.costedDeductions = 0,
    this.missingCostDeductions = 0,
    this.complete = true,
  });

  final int costedDeductions;
  final int missingCostDeductions;
  final bool complete;

  factory CostCoverage.fromJson(Map<String, dynamic> json) => CostCoverage(
    costedDeductions: (json['costed_deductions'] as num?)?.toInt() ?? 0,
    missingCostDeductions:
        (json['missing_cost_deductions'] as num?)?.toInt() ?? 0,
    complete: json['complete'] is bool ? json['complete'] as bool : true,
  );
}

/// Category-level sales & COGS breakdown for analytics charts.
class SalesCategoryBreakdown {
  const SalesCategoryBreakdown({
    required this.categoryId,
    required this.categoryName,
    required this.grossMerchandise,
    required this.discounts,
    required this.netMerchandise,
    this.cogs,
    this.missingCostDeductions = 0,
  });

  final int? categoryId;
  final String categoryName;
  final double grossMerchandise;
  final double discounts;
  final double netMerchandise;
  final double? cogs;
  final int missingCostDeductions;

  factory SalesCategoryBreakdown.fromJson(Map<String, dynamic> json) =>
      SalesCategoryBreakdown(
        categoryId: (json['category_id'] as num?)?.toInt(),
        categoryName: stringField(json, 'category_name'),
        grossMerchandise: optionalDecimalField(json, 'gross_merchandise'),
        discounts: optionalDecimalField(json, 'discounts'),
        netMerchandise: optionalDecimalField(json, 'net_merchandise'),
        cogs: nullableDecimalField(json, 'cogs'),
        missingCostDeductions:
            (json['missing_cost_deductions'] as num?)?.toInt() ?? 0,
      );
}

class VatBucketTotals {
  const VatBucketTotals({
    this.transactions = 0,
    this.grossSales = 0,
    this.vatableSales = 0,
    this.vat = 0,
  });

  final int transactions;
  final double grossSales;
  final double vatableSales;
  final double vat;

  factory VatBucketTotals.fromJson(Map<String, dynamic> json) =>
      VatBucketTotals(
        transactions: (json['transactions'] as num?)?.toInt() ?? 0,
        grossSales: optionalDecimalField(json, 'gross_sales'),
        vatableSales: optionalDecimalField(json, 'vatable_sales'),
        vat: optionalDecimalField(json, 'vat'),
      );
}

class OrVatSplit {
  const OrVatSplit({
    this.orBacked = const VatBucketTotals(),
    this.untaggedOs = const VatBucketTotals(),
    this.combined = const VatBucketTotals(),
  });

  final VatBucketTotals orBacked;
  final VatBucketTotals untaggedOs;
  final VatBucketTotals combined;

  factory OrVatSplit.fromJson(Map<String, dynamic> json) => OrVatSplit(
    orBacked: json['or_backed'] is Map<String, dynamic>
        ? VatBucketTotals.fromJson(json['or_backed'] as Map<String, dynamic>)
        : const VatBucketTotals(),
    untaggedOs: json['untagged_os'] is Map<String, dynamic>
        ? VatBucketTotals.fromJson(json['untagged_os'] as Map<String, dynamic>)
        : const VatBucketTotals(),
    combined: json['combined'] is Map<String, dynamic>
        ? VatBucketTotals.fromJson(json['combined'] as Map<String, dynamic>)
        : const VatBucketTotals(),
  );
}

class VatPeriodRow {
  const VatPeriodRow({
    required this.period,
    required this.transactions,
    required this.grossSales,
    required this.vat,
    required this.orBackedTransactions,
    required this.orBackedSales,
    required this.orBackedVatable,
    required this.orBackedVat,
    required this.untaggedTransactions,
    required this.untaggedSales,
    required this.untaggedVatable,
    required this.untaggedVat,
  });

  final String period;
  final int transactions;
  final double grossSales;
  final double vat;
  final int orBackedTransactions;
  final double orBackedSales;
  final double orBackedVatable;
  final double orBackedVat;
  final int untaggedTransactions;
  final double untaggedSales;
  final double untaggedVatable;
  final double untaggedVat;

  factory VatPeriodRow.fromJson(Map<String, dynamic> json) => VatPeriodRow(
    period: stringField(json, 'period'),
    transactions: (json['transactions'] as num?)?.toInt() ?? 0,
    grossSales: optionalDecimalField(json, 'gross_sales'),
    vat: optionalDecimalField(json, 'vat'),
    orBackedTransactions:
        (json['or_backed_transactions'] as num?)?.toInt() ?? 0,
    orBackedSales: optionalDecimalField(json, 'or_backed_sales'),
    orBackedVatable: optionalDecimalField(json, 'or_backed_vatable'),
    orBackedVat: optionalDecimalField(json, 'or_backed_vat'),
    untaggedTransactions: (json['untagged_transactions'] as num?)?.toInt() ?? 0,
    untaggedSales: optionalDecimalField(json, 'untagged_sales'),
    untaggedVatable: optionalDecimalField(json, 'untagged_vatable'),
    untaggedVat: optionalDecimalField(json, 'untagged_vat'),
  );
}

class VatReportSummary {
  const VatReportSummary({
    required this.from,
    required this.to,
    required this.granularity,
    required this.totals,
    required this.periods,
  });

  final String from;
  final String to;
  final String granularity;
  final OrVatSplit totals;
  final List<VatPeriodRow> periods;

  factory VatReportSummary.fromJson(Map<String, dynamic> json) =>
      VatReportSummary(
        from: stringField(json, 'from'),
        to: stringField(json, 'to'),
        granularity: (json['granularity'] as String?) ?? 'day',
        totals: json['totals'] is Map<String, dynamic>
            ? OrVatSplit.fromJson(json['totals'] as Map<String, dynamic>)
            : const OrVatSplit(),
        periods: nestedList(json, 'by_period', VatPeriodRow.fromJson),
      );
}

/// GET /api/v1/reports/sales-summary/
class SalesSummary {
  const SalesSummary({
    required this.from,
    required this.to,
    required this.totalTransactions,
    required this.totalGross,
    required this.totalVat,
    required this.totalDiscounts,
    required this.days,
    this.totalVatableSales = 0,
    this.totalPaymentFees = 0,
    this.totalDeliveryFees = 0,
    this.merchandiseGross,
    this.merchandiseNetExVat,
    this.totalCogs,
    this.grossProfit,
    this.grossMarginPercent,
    this.effectiveMarkupPercent,
    this.costCoverage = const CostCoverage(),
    this.categories = const [],
    this.orVatBreakdown,
    this.abv,
    this.asp,
    this.markdownPercent,
  });

  final String from;
  final String to;
  final int totalTransactions;
  final double totalGross;
  final double totalVatableSales;
  final double totalVat;
  final double totalDiscounts;
  final double totalPaymentFees;
  final double totalDeliveryFees;
  final double? merchandiseGross;
  final double? merchandiseNetExVat;
  final double? totalCogs;
  final double? grossProfit;
  final double? grossMarginPercent;
  final double? effectiveMarkupPercent;
  final CostCoverage costCoverage;
  final List<SalesDay> days;
  final List<SalesCategoryBreakdown> categories;
  final OrVatSplit? orVatBreakdown;

  /// Average bill value: invoice total ÷ bills. Null over an empty range.
  final double? abv;

  /// Average selling price: net merchandise ÷ BASE units sold.
  final double? asp;

  /// Markdown: discounts ÷ merchandise gross, as a percentage.
  final double? markdownPercent;

  bool get hasPaymentFees =>
      totalPaymentFees > 0 || days.any((day) => day.paymentFees > 0);

  bool get hasProfitBreakdown =>
      merchandiseGross != null ||
      merchandiseNetExVat != null ||
      totalCogs != null ||
      grossProfit != null ||
      !costCoverage.complete;

  factory SalesSummary.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'];
    if (totals is! Map<String, dynamic>) {
      throw FormatException('Missing required object field "totals"');
    }
    final days = json['by_day'];
    if (days is! List) {
      throw FormatException('Missing required list field "by_day"');
    }
    final coverageRaw = json['cost_coverage'];
    final categoriesRaw = json['by_category'];
    final orVatRaw = json['or_vat_breakdown'];
    return SalesSummary(
      from: stringField(json, 'from'),
      to: stringField(json, 'to'),
      totalTransactions: intField(totals, 'transactions'),
      totalGross: optionalDecimalField(totals, 'gross_sales'),
      totalVatableSales: optionalDecimalField(totals, 'vatable_sales'),
      totalVat: optionalDecimalField(totals, 'vat'),
      totalDiscounts: optionalDecimalField(totals, 'discounts'),
      totalPaymentFees: optionalDecimalField(totals, 'payment_fees'),
      totalDeliveryFees: optionalDecimalField(totals, 'delivery_fees'),
      merchandiseGross: nullableDecimalField(totals, 'merchandise_gross'),
      merchandiseNetExVat: nullableDecimalField(
        totals,
        'merchandise_net_ex_vat',
      ),
      totalCogs: nullableDecimalField(totals, 'cogs'),
      grossProfit: nullableDecimalField(totals, 'gross_profit'),
      grossMarginPercent: nullableDecimalField(totals, 'gross_margin_percent'),
      effectiveMarkupPercent: nullableDecimalField(
        totals,
        'effective_markup_percent',
      ),
      costCoverage: coverageRaw is Map<String, dynamic>
          ? CostCoverage.fromJson(coverageRaw)
          : const CostCoverage(),
      days: days
          .map((d) => SalesDay.fromJson(d as Map<String, dynamic>))
          .toList(),
      categories: categoriesRaw is List
          ? categoriesRaw
                .map(
                  (c) => SalesCategoryBreakdown.fromJson(
                    c as Map<String, dynamic>,
                  ),
                )
                .toList()
          : const [],
      orVatBreakdown: orVatRaw is Map<String, dynamic>
          ? OrVatSplit.fromJson(orVatRaw)
          : null,
      abv: nullableDecimalField(totals, 'abv'),
      asp: nullableDecimalField(totals, 'asp'),
      markdownPercent: nullableDecimalField(totals, 'markdown_percent'),
    );
  }
}

class SalesDay {
  const SalesDay({
    required this.day,
    required this.transactions,
    required this.gross,
    required this.vat,
    required this.discounts,
    this.paymentFees = 0,
    this.deliveryFees = 0,
    this.merchandiseNetExVat,
    this.cogs,
    this.grossProfit,
  });

  final String day;
  final int transactions;
  final double gross;
  final double vat;
  final double discounts;
  final double paymentFees;
  final double deliveryFees;
  final double? merchandiseNetExVat;
  final double? cogs;
  final double? grossProfit;

  factory SalesDay.fromJson(Map<String, dynamic> json) => SalesDay(
    day: stringField(json, 'day'),
    transactions: intField(json, 'transactions'),
    gross: optionalDecimalField(json, 'gross_sales'),
    vat: optionalDecimalField(json, 'vat'),
    discounts: optionalDecimalField(json, 'discounts'),
    paymentFees: optionalDecimalField(json, 'payment_fees'),
    deliveryFees: optionalDecimalField(json, 'delivery_fees'),
    merchandiseNetExVat: nullableDecimalField(json, 'merchandise_net_ex_vat'),
    cogs: nullableDecimalField(json, 'cogs'),
    grossProfit: nullableDecimalField(json, 'gross_profit'),
  );
}

/// GET /api/v1/reports/inventory-valuation/
class InventoryValuation {
  const InventoryValuation({
    required this.batchCount,
    required this.totalUnits,
    required this.totalCost,
    required this.totalRetail,
    required this.categories,
    this.locations = const [],
  });

  final int batchCount;
  final double totalUnits;
  final double totalCost;
  final double totalRetail;
  final List<ValuationCategory> categories;
  final List<ValuationLocation> locations;

  factory InventoryValuation.fromJson(Map<String, dynamic> json) {
    final totals = json['totals'];
    if (totals is! Map<String, dynamic>) {
      throw FormatException('Missing required object field "totals"');
    }
    final categories = json['by_category'];
    if (categories is! List) {
      throw FormatException('Missing required list field "by_category"');
    }
    final locations = json['by_location'];
    return InventoryValuation(
      batchCount: intField(totals, 'batch_count'),
      totalUnits: optionalDecimalField(totals, 'total_units'),
      totalCost: optionalDecimalField(totals, 'total_cost_value'),
      totalRetail: optionalDecimalField(totals, 'total_retail_value'),
      categories: categories
          .map((c) => ValuationCategory.fromJson(c as Map<String, dynamic>))
          .toList(),
      locations: locations is List
          ? locations
                .map(
                  (l) => ValuationLocation.fromJson(l as Map<String, dynamic>),
                )
                .toList()
          : const [],
    );
  }
}

class ValuationLocation {
  const ValuationLocation({
    required this.locationId,
    required this.locationName,
    required this.batchCount,
    required this.units,
    required this.cost,
    required this.retail,
  });

  final int? locationId;
  final String locationName;
  final int batchCount;
  final double units;
  final double cost;
  final double retail;

  factory ValuationLocation.fromJson(Map<String, dynamic> json) =>
      ValuationLocation(
        locationId: (json['location'] as num?)?.toInt(),
        locationName: stringField(json, 'location_name'),
        batchCount: intField(json, 'batch_count'),
        units: optionalDecimalField(json, 'total_units'),
        cost: optionalDecimalField(json, 'cost_value'),
        retail: optionalDecimalField(json, 'retail_value'),
      );
}

class ValuationCategory {
  const ValuationCategory({
    required this.id,
    required this.name,
    required this.batchCount,
    required this.units,
    required this.cost,
    required this.retail,
  });

  final int id;
  final String name;
  final int batchCount;
  final double units;
  final double cost;
  final double retail;

  factory ValuationCategory.fromJson(Map<String, dynamic> json) =>
      ValuationCategory(
        id: intField(json, 'variant__product__category__id'),
        name: stringField(json, 'variant__product__category__name'),
        batchCount: intField(json, 'batch_count'),
        units: optionalDecimalField(json, 'total_units'),
        cost: optionalDecimalField(json, 'cost_value'),
        retail: optionalDecimalField(json, 'retail_value'),
      );
}

/// GET /api/v1/reports/stock-movements/
class StockMovements {
  const StockMovements({
    required this.from,
    required this.to,
    required this.totalIn,
    required this.totalOut,
    required this.receiptsByDay,
    required this.adjustmentsByType,
  });

  final String from;
  final String to;
  final double totalIn;
  final double totalOut;
  final List<MovementDay> receiptsByDay;
  final List<MovementType> adjustmentsByType;

  factory StockMovements.fromJson(Map<String, dynamic> json) {
    final days = json['receipts_by_day'];
    if (days is! List) {
      throw FormatException('Missing required list field "receipts_by_day"');
    }
    final types = json['adjustments_by_type'];
    if (types is! List) {
      throw FormatException(
        'Missing required list field "adjustments_by_type"',
      );
    }
    return StockMovements(
      from: stringField(json, 'from'),
      to: stringField(json, 'to'),
      totalIn: optionalDecimalField(json, 'total_qty_in'),
      totalOut: optionalDecimalField(json, 'total_qty_out'),
      receiptsByDay: days
          .map((d) => MovementDay.fromJson(d as Map<String, dynamic>))
          .toList(),
      adjustmentsByType: types
          .map((t) => MovementType.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MovementDay {
  const MovementDay({
    required this.date,
    required this.receipts,
    required this.qtyIn,
  });

  final String date;
  final int receipts;
  final double qtyIn;

  factory MovementDay.fromJson(Map<String, dynamic> json) => MovementDay(
    date: stringField(json, 'receive_date'),
    receipts: intField(json, 'receipts'),
    qtyIn: optionalDecimalField(json, 'qty_in'),
  );
}

class MovementType {
  const MovementType({
    required this.type,
    required this.movements,
    required this.qtyOut,
  });

  final String type;
  final int movements;
  final double qtyOut;

  factory MovementType.fromJson(Map<String, dynamic> json) => MovementType(
    type: stringField(json, 'adjustment_type'),
    movements: intField(json, 'movements'),
    qtyOut: optionalDecimalField(json, 'qty_out'),
  );
}

/// GET /api/v1/reports/requisition-history/
class RequisitionHistory {
  const RequisitionHistory({
    required this.from,
    required this.to,
    required this.statusFilter,
    required this.countByStatus,
    required this.requisitions,
  });

  final String from;
  final String to;
  final String? statusFilter;
  final Map<String, int> countByStatus;
  final List<RequisitionHistoryRow> requisitions;

  factory RequisitionHistory.fromJson(Map<String, dynamic> json) {
    final counts = json['count_by_status'];
    if (counts is! List) {
      throw FormatException('Missing required list field "count_by_status"');
    }
    final rows = json['requisitions'];
    if (rows is! List) {
      throw FormatException('Missing required list field "requisitions"');
    }
    return RequisitionHistory(
      from: stringField(json, 'from'),
      to: stringField(json, 'to'),
      statusFilter: json['status_filter'] as String?,
      countByStatus: {
        for (final c in counts)
          stringField(c as Map<String, dynamic>, 'status'): intField(
            c,
            'count',
          ),
      },
      requisitions: rows
          .map((r) => RequisitionHistoryRow.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }
}

class RequisitionHistoryRow {
  const RequisitionHistoryRow({
    required this.id,
    required this.reqNumber,
    required this.status,
    required this.project,
    required this.requestedBy,
    required this.approvedBy,
    required this.createdAt,
  });

  final int id;
  final String reqNumber;
  final String status;
  final String project;
  final String requestedBy;
  final String? approvedBy;
  final String createdAt;

  factory RequisitionHistoryRow.fromJson(Map<String, dynamic> json) =>
      RequisitionHistoryRow(
        id: intField(json, 'id'),
        reqNumber: stringField(json, 'req_number'),
        status: stringField(json, 'status'),
        project: stringField(json, 'project'),
        requestedBy: stringField(json, 'requested_by'),
        approvedBy: json['approved_by'] as String?,
        createdAt: stringField(json, 'created_at'),
      );
}

// ---------------------------------------------------------------------------
// P1 sales detail reports. All seven answer through `_paged()` server-side:
// `from`, `to` and `totals` sit OUTSIDE the page, so the report's own numbers
// survive paging, and the rows arrive in `results` 50 at a time.
// ---------------------------------------------------------------------------

/// One page of a paginated report, plus how many rows the server holds in all.
class ReportPage<TRow> {
  const ReportPage({required this.count, required this.rows});

  /// Rows across every page, not just this one.
  final int count;
  final List<TRow> rows;

  factory ReportPage.fromJson(
    Map<String, dynamic> json,
    TRow Function(Map<String, dynamic>) row,
  ) {
    final results = json['results'];
    if (results is! List) {
      throw FormatException('Missing required list field "results"');
    }
    return ReportPage(
      count: (json['count'] as num?)?.toInt() ?? results.length,
      rows: [for (final item in results) row(item as Map<String, dynamic>)],
    );
  }
}

/// The `totals` object every paged report carries. Missing is a broken body,
/// not an empty range: the totals exist even when the page holds no rows.
Map<String, dynamic> totalsField(Map<String, dynamic> json) {
  final totals = json['totals'];
  if (totals is! Map<String, dynamic>) {
    throw FormatException('Missing required object field "totals"');
  }
  return totals;
}

/// A `{method: pesos}` map, as bill-wise reports tenders.
Map<String, double> methodsField(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw == null) return const {};
  if (raw is! Map) {
    throw FormatException('Field "$key" is not an object: ${raw.runtimeType}');
  }
  return {
    for (final entry in raw.entries)
      entry.key.toString(): optionalDecimalField({key: entry.value}, key),
  };
}

/// GET /api/v1/reports/sales-by-item/
class SalesByItemReport {
  const SalesByItemReport({
    required this.from,
    required this.to,
    required this.variantCount,
    required this.totalQtyBase,
    required this.totalNet,
    required this.totalCogs,
    required this.totalGrossProfit,
    required this.missingCostDeductions,
    required this.page,
  });

  final String from;
  final String to;
  final int variantCount;
  final double totalQtyBase;
  final double totalNet;

  /// Null when no deduction in the range carried a cost: unknown, never ₱0.
  final double? totalCogs;
  final double? totalGrossProfit;
  final int missingCostDeductions;
  final ReportPage<ItemSalesRow> page;

  factory SalesByItemReport.fromJson(Map<String, dynamic> json) {
    final totals = totalsField(json);
    return SalesByItemReport(
      from: stringField(json, 'from'),
      to: stringField(json, 'to'),
      variantCount: (totals['variant_count'] as num?)?.toInt() ?? 0,
      totalQtyBase: optionalDecimalField(totals, 'qty_base'),
      totalNet: optionalDecimalField(totals, 'net_merchandise'),
      totalCogs: nullableDecimalField(totals, 'cogs'),
      totalGrossProfit: nullableDecimalField(totals, 'gross_profit'),
      missingCostDeductions:
          (totals['missing_cost_deductions'] as num?)?.toInt() ?? 0,
      page: ReportPage.fromJson(json, ItemSalesRow.fromJson),
    );
  }
}

class ItemSalesRow {
  const ItemSalesRow({
    required this.sku,
    required this.product,
    required this.variant,
    required this.uom,
    required this.qtyBase,
    required this.gross,
    required this.discounts,
    required this.net,
    required this.cogs,
    required this.grossProfit,
    required this.missingCostDeductions,
  });

  final String sku;
  final String product;
  final String variant;
  final String uom;

  /// Base units: a selling unit of 2 bags counts as 2.
  final double qtyBase;
  final double gross;
  final double discounts;
  final double net;
  final double? cogs;
  final double? grossProfit;
  final int missingCostDeductions;

  /// What the table calls this item: `Coke · 1.5L`.
  String get name => variant.trim().isEmpty ? product : '$product · $variant';

  factory ItemSalesRow.fromJson(Map<String, dynamic> json) => ItemSalesRow(
    sku: stringField(json, 'sku'),
    product: stringField(json, 'product'),
    variant: json['variant'] as String? ?? '',
    uom: json['uom'] as String? ?? '',
    qtyBase: optionalDecimalField(json, 'qty_base'),
    gross: optionalDecimalField(json, 'merchandise_gross'),
    discounts: optionalDecimalField(json, 'discounts'),
    net: optionalDecimalField(json, 'net_merchandise'),
    cogs: nullableDecimalField(json, 'cogs'),
    grossProfit: nullableDecimalField(json, 'gross_profit'),
    missingCostDeductions:
        (json['missing_cost_deductions'] as num?)?.toInt() ?? 0,
  );
}

/// GET /api/v1/reports/sales-by-hour/
class SalesByHour {
  const SalesByHour({
    required this.from,
    required this.to,
    required this.totalTransactions,
    required this.totalInvoice,
    required this.page,
  });

  final String from;
  final String to;
  final int totalTransactions;
  final double totalInvoice;
  final ReportPage<HourlySalesRow> page;

  factory SalesByHour.fromJson(Map<String, dynamic> json) {
    final totals = totalsField(json);
    return SalesByHour(
      from: stringField(json, 'from'),
      to: stringField(json, 'to'),
      totalTransactions: (totals['transactions'] as num?)?.toInt() ?? 0,
      totalInvoice: optionalDecimalField(totals, 'invoice_total'),
      page: ReportPage.fromJson(json, HourlySalesRow.fromJson),
    );
  }
}

class HourlySalesRow {
  const HourlySalesRow({
    required this.hour,
    required this.transactions,
    required this.invoiceTotal,
  });

  /// Store-local hour, 0-23. Every hour is returned, zeros included.
  final int hour;
  final int transactions;
  final double invoiceTotal;

  factory HourlySalesRow.fromJson(Map<String, dynamic> json) => HourlySalesRow(
    hour: (json['hour'] as num?)?.toInt() ?? 0,
    transactions: (json['transactions'] as num?)?.toInt() ?? 0,
    invoiceTotal: optionalDecimalField(json, 'invoice_total'),
  );
}

/// GET /api/v1/reports/sales-by-cashier/
class SalesByCashier {
  const SalesByCashier({
    required this.from,
    required this.to,
    required this.totalTransactions,
    required this.totalInvoice,
    required this.totalDiscounts,
    required this.page,
  });

  final String from;
  final String to;
  final int totalTransactions;
  final double totalInvoice;
  final double totalDiscounts;
  final ReportPage<CashierSalesRow> page;

  factory SalesByCashier.fromJson(Map<String, dynamic> json) {
    final totals = totalsField(json);
    return SalesByCashier(
      from: stringField(json, 'from'),
      to: stringField(json, 'to'),
      totalTransactions: (totals['transactions'] as num?)?.toInt() ?? 0,
      totalInvoice: optionalDecimalField(totals, 'invoice_total'),
      totalDiscounts: optionalDecimalField(totals, 'discounts'),
      page: ReportPage.fromJson(json, CashierSalesRow.fromJson),
    );
  }
}

class CashierSalesRow {
  const CashierSalesRow({
    required this.cashierName,
    required this.username,
    required this.transactions,
    required this.invoiceTotal,
    required this.discounts,
  });

  final String cashierName;
  final String username;
  final int transactions;
  final double invoiceTotal;
  final double discounts;

  factory CashierSalesRow.fromJson(Map<String, dynamic> json) =>
      CashierSalesRow(
        cashierName: stringField(json, 'cashier_name'),
        username: json['username'] as String? ?? '',
        transactions: (json['transactions'] as num?)?.toInt() ?? 0,
        invoiceTotal: optionalDecimalField(json, 'invoice_total'),
        discounts: optionalDecimalField(json, 'discounts'),
      );
}

/// GET /api/v1/reports/bill-wise/
class BillWiseReport {
  const BillWiseReport({
    required this.from,
    required this.to,
    required this.totalTransactions,
    required this.totalDiscount,
    required this.totalGrand,
    required this.totalMethods,
    required this.page,
  });

  final String from;
  final String to;
  final int totalTransactions;
  final double totalDiscount;
  final double totalGrand;

  /// Tendered pesos per method across the whole range, change already off.
  final Map<String, double> totalMethods;
  final ReportPage<BillWiseRow> page;

  factory BillWiseReport.fromJson(Map<String, dynamic> json) {
    final totals = totalsField(json);
    return BillWiseReport(
      from: stringField(json, 'from'),
      to: stringField(json, 'to'),
      totalTransactions: (totals['transactions'] as num?)?.toInt() ?? 0,
      totalDiscount: optionalDecimalField(totals, 'discount'),
      totalGrand: optionalDecimalField(totals, 'grand_total'),
      totalMethods: methodsField(totals, 'methods'),
      page: ReportPage.fromJson(json, BillWiseRow.fromJson),
    );
  }
}

class BillWiseRow {
  const BillWiseRow({
    required this.id,
    required this.transactionNo,
    required this.orNumber,
    required this.invoiceNo,
    required this.date,
    required this.cashierName,
    required this.methods,
    required this.discount,
    required this.grandTotal,
  });

  final int id;
  final String transactionNo;
  final String orNumber;
  final String invoiceNo;

  /// Local ISO timestamp, e.g. `2026-10-29T14:14:00+08:00`.
  final String date;
  final String cashierName;
  final Map<String, double> methods;
  final double discount;

  /// Signed: a RETURN bill is listed here with its negative total.
  final double grandTotal;

  factory BillWiseRow.fromJson(Map<String, dynamic> json) => BillWiseRow(
    id: (json['id'] as num?)?.toInt() ?? 0,
    transactionNo: stringField(json, 'transaction_no'),
    orNumber: json['or_number'] as String? ?? '',
    invoiceNo: json['invoice_no'] as String? ?? '',
    date: stringField(json, 'date'),
    cashierName: stringField(json, 'cashier_name'),
    methods: methodsField(json, 'methods'),
    discount: optionalDecimalField(json, 'discount'),
    grandTotal: optionalDecimalField(json, 'grand_total'),
  );
}

/// GET /api/v1/reports/returns-exchanges/
class ReturnsExchangesReport {
  const ReturnsExchangesReport({
    required this.from,
    required this.to,
    required this.totalTransactions,
    required this.totalReturns,
    required this.totalExchanges,
    required this.totalRefunded,
    required this.page,
  });

  final String from;
  final String to;
  final int totalTransactions;
  final int totalReturns;
  final int totalExchanges;
  final double totalRefunded;
  final ReportPage<ReversalRow> page;

  factory ReturnsExchangesReport.fromJson(Map<String, dynamic> json) {
    final totals = totalsField(json);
    return ReturnsExchangesReport(
      from: stringField(json, 'from'),
      to: stringField(json, 'to'),
      totalTransactions: (totals['transactions'] as num?)?.toInt() ?? 0,
      totalReturns: (totals['returns'] as num?)?.toInt() ?? 0,
      totalExchanges: (totals['exchanges'] as num?)?.toInt() ?? 0,
      totalRefunded: optionalDecimalField(totals, 'refunded'),
      page: ReportPage.fromJson(json, ReversalRow.fromJson),
    );
  }
}

class ReversalRow {
  const ReversalRow({
    required this.transactionNo,
    required this.date,
    required this.source,
    required this.cashierName,
    required this.originalTransactionNo,
    required this.refunded,
    required this.grandTotal,
    required this.reason,
  });

  final String transactionNo;
  final String date;

  /// `RETURN` or `EXCHANGE`.
  final String source;
  final String cashierName;
  final String originalTransactionNo;

  /// Money handed BACK: positive on a cash return, 0.00 on an exchange.
  final double refunded;
  final double grandTotal;

  /// The note on file, null when nobody wrote one.
  final String? reason;

  factory ReversalRow.fromJson(Map<String, dynamic> json) => ReversalRow(
    transactionNo: stringField(json, 'transaction_no'),
    date: stringField(json, 'date'),
    source: stringField(json, 'source'),
    cashierName: stringField(json, 'cashier_name'),
    originalTransactionNo: json['original_transaction_no'] as String? ?? '',
    refunded: optionalDecimalField(json, 'refunded'),
    grandTotal: optionalDecimalField(json, 'grand_total'),
    reason: json['reason'] as String?,
  );
}

/// GET /api/v1/reports/discounts/
class DiscountsReport {
  const DiscountsReport({
    required this.from,
    required this.to,
    required this.totalLineDiscount,
    required this.totalCartDiscount,
    required this.totalApprovalDiscount,
    required this.approvals,
    required this.totalDiscount,
    required this.page,
  });

  final String from;
  final String to;
  final double totalLineDiscount;
  final double totalCartDiscount;

  /// The CART discount on the sales a manager signed off — not extra money.
  final double totalApprovalDiscount;
  final int approvals;

  /// LINE + CART only.
  final double totalDiscount;
  final ReportPage<DiscountTypeRow> page;

  factory DiscountsReport.fromJson(Map<String, dynamic> json) {
    final totals = totalsField(json);
    return DiscountsReport(
      from: stringField(json, 'from'),
      to: stringField(json, 'to'),
      totalLineDiscount: optionalDecimalField(totals, 'line_discount'),
      totalCartDiscount: optionalDecimalField(totals, 'cart_discount'),
      totalApprovalDiscount: optionalDecimalField(totals, 'approval_discount'),
      approvals: (totals['approvals'] as num?)?.toInt() ?? 0,
      totalDiscount: optionalDecimalField(totals, 'total_discount'),
      page: ReportPage.fromJson(json, DiscountTypeRow.fromJson),
    );
  }
}

class DiscountTypeRow {
  const DiscountTypeRow({
    required this.type,
    required this.transactions,
    required this.totalDiscount,
    required this.approvals,
  });

  /// `LINE`, `CART` or `APPROVAL`.
  final String type;
  final int transactions;
  final double totalDiscount;

  /// Only the APPROVAL row carries an approval count.
  final int? approvals;

  factory DiscountTypeRow.fromJson(Map<String, dynamic> json) =>
      DiscountTypeRow(
        type: stringField(json, 'type'),
        transactions: (json['transactions'] as num?)?.toInt() ?? 0,
        totalDiscount: optionalDecimalField(json, 'total_discount'),
        approvals: (json['approvals'] as num?)?.toInt(),
      );
}

/// GET /api/v1/reports/voids/
class VoidsReport {
  const VoidsReport({
    required this.from,
    required this.to,
    required this.totalTransactions,
    required this.totalVoided,
    required this.page,
  });

  final String from;
  final String to;
  final int totalTransactions;
  final double totalVoided;
  final ReportPage<VoidRow> page;

  factory VoidsReport.fromJson(Map<String, dynamic> json) {
    final totals = totalsField(json);
    return VoidsReport(
      from: stringField(json, 'from'),
      to: stringField(json, 'to'),
      totalTransactions: (totals['transactions'] as num?)?.toInt() ?? 0,
      totalVoided: optionalDecimalField(totals, 'voided_total'),
      page: ReportPage.fromJson(json, VoidRow.fromJson),
    );
  }
}

class VoidRow {
  const VoidRow({
    required this.transactionNo,
    required this.date,
    required this.cashierName,
    required this.voidedTotal,
    required this.reason,
  });

  final String transactionNo;
  final String date;
  final String cashierName;
  final double voidedTotal;

  /// The row's note, null when the till was left blank.
  final String? reason;

  factory VoidRow.fromJson(Map<String, dynamic> json) => VoidRow(
    transactionNo: stringField(json, 'transaction_no'),
    date: stringField(json, 'date'),
    cashierName: stringField(json, 'cashier_name'),
    voidedTotal: optionalDecimalField(json, 'voided_total'),
    reason: json['reason'] as String?,
  );
}
