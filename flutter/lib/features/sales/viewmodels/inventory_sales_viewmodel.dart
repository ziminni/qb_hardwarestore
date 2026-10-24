import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:flutter/foundation.dart';

class InventorySalesViewmodel extends ChangeNotifier {
  InventorySalesViewmodel({SalesService? service})
    : _service = service ?? SalesService();

  final SalesService _service;

  List<InventorySale> _sales = const [];
  List<InventoryReturn> _returns = const [];
  bool _isLoading = false;
  String? _loadError;

  List<InventorySale> get sales => List.unmodifiable(_sales);
  List<InventoryReturn> get returns => List.unmodifiable(_returns);
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  double get completedRevenue => _sales
      .where((sale) => sale.status == InventorySaleStatus.completed)
      .fold(0, (sum, sale) => sum + sale.total);

  /// Revenue net of refunds. RETURN rows carry negative grand totals on the
  /// wire precisely so they net — omitting them overstates month-end revenue.
  double get netRevenue =>
      completedRevenue +
      _returns.fold<double>(0, (sum, item) => sum + item.total);
  double get soldUnits => _sales
      .where((sale) => sale.status == InventorySaleStatus.completed)
      .fold(0, (sum, sale) => sum + sale.totalQuantity);
  int get completedReturns => _returns
      .where((item) => item.status == InventoryReturnStatus.completed)
      .length;

  /// Loads every sales transaction once and splits it in memory.
  ///
  /// Returns are `SalesTransaction` rows with `source='RETURN'` (decision 15),
  /// so no second endpoint is involved — the same list feeds the dashboard,
  /// the transactions table and the returns page. A failed load keeps the rows
  /// already shown: emptying the table would read as "no sales".
  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    notifyListeners();
    try {
      final rows = await _service.fetchTransactions();
      final byId = {for (final r in rows) r.id: r.transactionNo};
      _sales = [
        for (final r in rows)
          if (r.source != 'RETURN') _saleOf(r),
      ];
      _returns = [
        for (final r in rows)
          if (r.source == 'RETURN') _returnOf(r, byId),
      ];
      _loadError = null;
    } on SalesServiceException catch (error) {
      _loadError = error.message;
    } on FormatException catch (error) {
      // An unknown source or status is a contract break, not a crash: it
      // reaches the screen as an error the user can report and retry.
      _loadError = error.message;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  InventorySale _saleOf(TransactionRecord r) => InventorySale(
    transactionNo: r.transactionNo,
    date: r.transDate,
    customer: r.customerName,
    cashier: r.cashierName,
    paymentMethod: r.payments.isEmpty ? '—' : r.payments.first.method,
    source: _sourceLabel(r.source),
    status: _saleStatus(r.status),
    // The View sheet shows how it was paid and how much, so the payment rows
    // ride along instead of being reduced to their first method name.
    payments: [
      for (final p in r.payments)
        InventorySalePayment(method: p.method, amount: p.amountTendered),
    ],
    lines: [
      // The wire carries no product names — only the selling-unit code — and
      // line details render nowhere today, so the code stands in for both the
      // product name and the SKU rather than inventing either.
      for (final i in r.items)
        InventorySaleLine(
          productName: i.variantUomCode,
          variantName: i.variantUomCode,
          sku: i.variantUomCode,
          quantity: i.qty,
          unitPrice: i.unitPrice,
        ),
    ],
  );

  InventoryReturn _returnOf(
    TransactionRecord r,
    Map<int, String> transactionNos,
  ) {
    final original = r.originalTransactionId;
    return InventoryReturn(
      reference: r.transactionNo,
      date: r.transDate,
      type: InventoryReturnType.customer,
      relatedReference: original == null
          ? '—'
          : (transactionNos[original] ?? 'TRX-$original'),
      productName: r.items.isEmpty ? '—' : r.items.first.variantUomCode,
      variantName: r.items.isEmpty ? '—' : r.items.first.variantUomCode,
      sku: r.items.isEmpty ? '—' : r.items.first.variantUomCode,
      quantity: r.items.fold<double>(0, (sum, i) => sum + i.qty.abs()),
      reason: 'Customer return',
      status: _returnStatus(r.status),
      processedBy: r.cashierName,
      total: r.grandTotal,
      lines: [
        for (final i in r.items)
          InventorySaleLine(
            productName: i.variantUomCode,
            variantName: i.variantUomCode,
            sku: i.variantUomCode,
            quantity: i.qty,
            unitPrice: i.unitPrice,
          ),
      ],
    );
  }

  InventoryReturnStatus _returnStatus(String api) {
    // RETURN rows post final: the server has no pending-return state, so
    // pending/approved never occur and a zero pending count is true, not a lie.
    switch (api) {
      case 'COMPLETED':
        return InventoryReturnStatus.completed;
      case 'VOID':
        // A voided return was not honored; rejected is the closest member.
        return InventoryReturnStatus.rejected;
      case 'REFUNDED':
        return InventoryReturnStatus.completed;
      default:
        throw FormatException('Unknown return status: "$api"');
    }
  }

  String _sourceLabel(String api) {
    switch (api) {
      case 'WALK_IN':
        return 'Walk-in';
      case 'REQUISITION':
        return 'Requisition';
      case 'RETURN':
        return 'Return';
      default:
        throw FormatException('Unknown transaction source: "$api"');
    }
  }

  InventorySaleStatus _saleStatus(String api) {
    switch (api) {
      case 'COMPLETED':
        return InventorySaleStatus.completed;
      case 'VOID':
        return InventorySaleStatus.voided;
      case 'REFUNDED':
        return InventorySaleStatus.refunded;
      default:
        throw FormatException('Unknown transaction status: "$api"');
    }
  }
}
