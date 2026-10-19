import 'package:client/data/models/customer.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubSalesService extends SalesService {
  _StubSalesService() : super();

  List<QuotationRecord> quotations = const [];
  List<SalesOrderRow> orders = const [];
  String? failure;

  @override
  Future<List<QuotationRecord>> fetchQuotations() async {
    final failure = this.failure;
    if (failure != null) throw SalesServiceException(failure);
    return quotations;
  }

  @override
  Future<List<SalesOrderRow>> fetchSalesOrders() async {
    final failure = this.failure;
    if (failure != null) throw SalesServiceException(failure);
    return orders;
  }

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) =>
      throw UnimplementedError();
}

class _StubCustomerService extends CustomerService {
  _StubCustomerService() : super();

  List<Customer> customers = const [];

  @override
  Future<List<Customer>> fetchCustomers() async => customers;
}

QuotationRecord _quote() => const QuotationRecord(
  id: 1, number: 'QT-20261019-0001', customerId: 3, status: 'SENT',
  validUntil: '2026-11-19', createdAt: '2026-10-19T08:00:00Z', items: [],
);

SalesOrderRow _order() => const SalesOrderRow(
  id: 7, number: 'SO-20261019-0001', customerId: 3, quotationId: 1,
  status: 'CONFIRMED', createdAt: '2026-10-19T08:00:00Z', items: [],
);

Customer _customer() => const Customer(id: 3, name: 'Dela Cruz Construction', customerType: 'CONSTRUCTION_FIRM');

void main() {
  late _StubSalesService sales;
  late _StubCustomerService customers;
  late SalesModuleViewmodel viewmodel;

  setUp(() {
    sales = _StubSalesService();
    customers = _StubCustomerService();
    viewmodel = SalesModuleViewmodel(service: sales, customerService: customers);
  });

  test('quotations and orders load live with joined customer names', () async {
    sales.quotations = [_quote()];
    sales.orders = [_order()];
    customers.customers = [_customer()];

    await viewmodel.load();

    expect(viewmodel.quotations.single.number, 'QT-20261019-0001');
    expect(viewmodel.quotations.single.customer, 'Dela Cruz Construction');
    expect(viewmodel.orders.single.number, 'SO-20261019-0001');
    expect(viewmodel.loadError, isNull);
  });

  test('a failed load keeps the rows it already had', () async {
    sales.quotations = [_quote()];
    sales.orders = [_order()];
    customers.customers = [_customer()];
    await viewmodel.load();
    sales.failure = 'Cannot connect to the BuildPro server.';

    await viewmodel.load();

    expect(viewmodel.loadError, contains('Cannot connect'));
    expect(viewmodel.quotations, hasLength(1));
  });
}
