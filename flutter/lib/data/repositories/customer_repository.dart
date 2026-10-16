import 'package:client/data/models/customer.dart';
import 'package:client/data/services/customer_service.dart';

/// The repository layer between the POS checkout and the customer API.
///
/// It exists to keep the map's one-data-path invariant intact —
/// `View → ViewModel → Repository → Service → ApiClient` — so the customer step never talks
/// to Dio directly, and swapping the transport later touches this file rather than every
/// caller. Deliberately a pass-through holding **no policy**: a second copy of decision 14's
/// rules (who may owe, what the counter form captures) would be a second authority over them.
/// Same shape as [PosRepository] and [ProductsRepository].
class CustomerRepository {
  CustomerRepository(this.service);

  final CustomerService service;

  Future<List<Customer>> fetchCustomers() => service.fetchCustomers();

  Future<Customer> createCustomer({
    required String name,
    required CustomerType type,
  }) => service.createCustomer(name: name, type: type);

  Future<CustomerLedgerSummary> fetchLedgerSummary(int customerId) =>
      service.fetchLedgerSummary(customerId);
}
