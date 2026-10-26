import 'package:client/data/models/reports.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubReportsRepository extends ReportsRepository {
  _StubReportsRepository() : super();

  SalesSummary summary = const SalesSummary(
    from: '2026-09-26',
    to: '2026-10-25',
    totalTransactions: 40,
    totalGross: 9000,
    totalVat: 0,
    totalDiscounts: 0,
    days: [],
  );
  String? failure;

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
    final failure = this.failure;
    if (failure != null) throw ReportsServiceException(failure);
    return summary;
  }
}

class _StubSalesService extends SalesService {
  _StubSalesService() : super();

  List<TransactionRecord> rows = const [];
  String? failure;

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async {
    final failure = this.failure;
    if (failure != null) throw SalesServiceException(failure);
    return rows;
  }

  @override
  Future<List<QuotationRecord>> fetchQuotations() =>
      throw UnimplementedError();

  @override
  Future<List<SalesOrderRow>> fetchSalesOrders() =>
      throw UnimplementedError();
}

TransactionRecord _sale() => TransactionRecord(
  id: 9, transactionNo: 'TRX-20261019-0001',
  transDate: DateTime(2026, 10, 19, 8), customerId: 3,
  customerName: 'Dela Cruz Construction', cashierName: 'Cashy Ir',
  source: 'WALK_IN', originalTransactionId: null, status: 'COMPLETED',
  grandTotal: 100,
  items: const [TransactionLineItem(variantUomId: 1, variantUomCode: 'BAG', qty: 2, unitPrice: 50, subtotal: 100)],
  payments: const [TransactionPayment(method: 'CASH', amountTendered: 100)],
);

TransactionRecord _return() => TransactionRecord(
  id: 10, transactionNo: 'TRX-20261019-0002',
  transDate: DateTime(2026, 10, 19, 9), customerId: 3,
  customerName: 'Dela Cruz Construction', cashierName: 'Cashy Ir',
  source: 'RETURN', originalTransactionId: 9, status: 'COMPLETED',
  grandTotal: -50,
  items: const [TransactionLineItem(variantUomId: 1, variantUomCode: 'BAG', qty: -1, unitPrice: 50, subtotal: -50)],
  payments: const [TransactionPayment(method: 'CASH', amountTendered: -50)],
);

TransactionRecord _row({
  required String source,
  int? original,
  double total = -50,
  String status = 'COMPLETED',
  String no = 'TRX-20261019-0002',
}) => TransactionRecord(
  id: 10, transactionNo: no, transDate: DateTime(2026, 10, 19, 9),
  customerId: 3, customerName: 'Dela Cruz Construction', cashierName: 'Cashy Ir',
  source: source, originalTransactionId: original, status: status,
  grandTotal: total,
  items: const [TransactionLineItem(variantUomId: 1, variantUomCode: 'BAG', qty: -1, unitPrice: 50, subtotal: -50)],
  payments: const [TransactionPayment(method: 'CASH', amountTendered: -50)],
);

void main() {
  late _StubSalesService service;
  late _StubReportsRepository reports;
  late InventorySalesViewmodel viewmodel;

  setUp(() {
    service = _StubSalesService();
    reports = _StubReportsRepository();
    viewmodel = InventorySalesViewmodel(service: service, reports: reports);
  });

  // Phase 5 Task 3: tiles read the server summary (correct at any scale),
  // not the client fold of a capped transaction walk.
  test('loadSummary exposes server totals', () async {
    await viewmodel.loadSummary();

    expect(viewmodel.summary?.totalGross, 9000);
    expect(viewmodel.summary?.totalTransactions, 40);
    expect(viewmodel.summaryError, isNull);
  });

  test('a failed summary names the failure and keeps no stale totals', () async {
    reports.failure = 'Cannot connect to the BuildPro server.';

    await viewmodel.loadSummary();

    expect(viewmodel.summary, isNull);
    expect(viewmodel.summaryError, contains('Cannot connect'));
  });

  test('sales load live and returns derive from RETURN rows', () async {
    service.rows = [_sale(), _return()];

    await viewmodel.load();

    expect(viewmodel.sales.map((s) => s.transactionNo), ['TRX-20261019-0001']);
    expect(viewmodel.completedRevenue, 100);
    expect(viewmodel.returns.map((r) => r.reference), ['TRX-20261019-0002']);
    expect(viewmodel.returns.single.relatedReference, 'TRX-20261019-0001');
    expect(viewmodel.loadError, isNull);
  });

  test('a failed load keeps the rows it already had', () async {
    service.rows = [_sale()];
    await viewmodel.load();
    service.rows = const [];
    service.failure = 'Cannot connect to the BuildPro server.';

    await viewmodel.load();

    expect(viewmodel.loadError, contains('Cannot connect'));
    expect(viewmodel.sales, hasLength(1));
  });

  group('fix pass: reviewer 43db5223', () {

    test('a VOID return reads as rejected, not completed', () async {
      service.rows = [_row(source: 'RETURN', original: 9, status: 'VOID')];

      await viewmodel.load();

      expect(viewmodel.returns.single.status, InventoryReturnStatus.rejected);
    });

    test('net revenue subtracts the refunded amounts', () async {
      service.rows = [_sale(), _row(source: 'RETURN', original: 9)];

      await viewmodel.load();

      expect(viewmodel.completedRevenue, 100);
      expect(viewmodel.netRevenue, 50);
    });

    test('an unknown source lands in loadError instead of escaping', () async {
      service.rows = [_row(source: 'MYSTERY')];

      await viewmodel.load();

      expect(viewmodel.loadError, contains('MYSTERY'));
      expect(viewmodel.sales, isEmpty);
    });
  });
}
