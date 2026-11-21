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
