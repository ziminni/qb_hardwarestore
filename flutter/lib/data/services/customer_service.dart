import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/customer.dart';
import 'package:dio/dio.dart';

/// Raised when the customer API cannot be reached or answers unexpectedly.
///
/// [message] is safe to show a cashier.
class CustomerServiceException implements Exception {
  const CustomerServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The POS's customer master data (decision 14).
///
/// Three operations, and deliberately no more:
///
/// * **list** — the counter's picker over existing customers.
/// * **create** — a new utang customer at the till, on a **name + type** record only. The
///   backend already permits this: `CustomerViewSet` inherits `IsPOSOrReadOnly`, so a
///   Cashier may POST, which is why mid-sale creation needed no permission change.
/// * **one customer's utang** — read from `/api/v1/ledgers/aging/`, which returns exactly the
///   figures the panel shows, so no client-side summing and no second call.
///
/// There is no delete. `DELETE /customers/` exists and a Cashier could call it, but removing
/// a customer with transactions breaks the `on_delete=PROTECT` FK and destroys the audit
/// trail, so decision 14 wires no delete (its invariant 5).
class CustomerService {
  CustomerService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const customersPath = '/api/v1/customers/';
  static const agingPath = '/api/v1/ledgers/aging/';

  /// Every customer the server knows, for the picker.
  Future<List<Customer>> fetchCustomers() async {
    try {
      final page = await _client.getList<Customer>(
        customersPath,
        Customer.fromJson,
      );
      return page.items;
    } on DioException catch (error) {
      throw CustomerServiceException(_message(error));
    }
  }

  /// Creates a customer from the **minimal counter record**.
  ///
  /// Sends `name` and `customer_type` and nothing else. `contact_details`, `tin_no` and
  /// `total_credit_limit` keep their model defaults, because decision 14's locked decision 1
  /// keeps credit control out of the cashier's hands at the till.
  Future<Customer> createCustomer({
    required String name,
    required CustomerType type,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        customersPath,
        data: {'name': name, 'customer_type': type.apiValue},
      );
      return Customer.fromJson(response.data!);
    } on DioException catch (error) {
      throw CustomerServiceException(_message(error));
    }
  }

  /// One customer's outstanding utang.
  ///
  /// Returns a [CustomerLedgerSummary.empty] when the aging report does not mention the
  /// customer, which is the commonest case at the till and means "owes nothing" — **not** an
  /// error. Reporting a failure there would put an error in front of the cashier for the
  /// normal case.
  Future<CustomerLedgerSummary> fetchLedgerSummary(int customerId) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(agingPath);
      final body = response.data;
      if (body is! Map<String, dynamic>) {
        throw const FormatException('The aging report was not an object.');
      }
      final groups = body['groups'];
      if (groups is! List) {
        throw const FormatException('The aging report carried no groups list.');
      }
      for (final entry in groups) {
        if (entry is! Map<String, dynamic>) continue;
        if (entry['customer_id'] == customerId) {
          return CustomerLedgerSummary.fromJson(entry);
        }
      }
      return CustomerLedgerSummary.empty(customerId);
    } on DioException catch (error) {
      throw CustomerServiceException(_message(error));
    }
  }

  String _message(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    final response = error.response;
    if (response != null && response.statusCode == 401) {
      return 'Your session has expired. Sign in again.';
    }
    return 'The customer list could not be loaded.';
  }
}
