import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/supplier_payables.dart';
import 'package:dio/dio.dart';

/// Raised when payables cannot be read or a payment is refused. [message] is
/// safe to show.
class PayablesServiceException implements Exception {
  const PayablesServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads supplier bills and writes supplier payments (Phase 5 B2 wire, F2
/// screens; ENDPOINTS.md §3.3).
///
/// Three facts shape this class:
/// * a bill is written by `POST /goods-receipts/{id}/process/`, never by the
///   client, so every bill route here is a READ;
/// * `PUT`/`PATCH`/`DELETE` on a payment answer 405 for every role, so a
///   payment that is wrong is refused rather than corrected — there is no edit
///   method to call;
/// * the server's refusal `detail` names the bill, the balance and the amount
///   typed. It is shown BEFORE any canned sentence, because a canned one cannot
///   say which of those went wrong.
class PayablesService {
  PayablesService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const billsPath = '/api/v1/supplier-bills/';
  static const paymentsPath = '/api/v1/supplier-payments/';
  static const summaryPath = '/api/v1/suppliers/payables/';

  /// Every bill, oldest due first (the server orders by `due_date`, then id).
  ///
  /// The filters are the server's own (`?supplier=`, `?status=`, `?overdue=`),
  /// so a filtered read is the server's answer, not a client-side narrowing of
  /// one page.
  Future<List<SupplierBill>> fetchBills({
    int? supplierId,
    SupplierBillStatus? status,
    bool overdueOnly = false,
  }) => _readAll(
    billsPath,
    SupplierBill.fromJson,
    'The supplier bills could not be loaded.',
    query: {
      'supplier': ?supplierId,
      if (status != null) 'status': status.code,
      if (overdueOnly) 'overdue': true,
    },
  );

  /// One bill with its full payment history — re-read after a payment so the
  /// dialog shows the balance the server now holds.
  Future<SupplierBill> fetchBill(int id) async {
    try {
      final response = await _client.get<dynamic>('$billsPath$id/');
      final body = response.data;
      if (body is! Map<String, dynamic>) {
        throw const FormatException('A bill is a single object.');
      }
      return SupplierBill.fromJson(body);
    } on DioException catch (error) {
      throw PayablesServiceException(
        _message(error, 'The bill could not be loaded.'),
      );
    } on FormatException catch (error) {
      throw PayablesServiceException(
        'The bill could not be loaded. (${error.message})',
      );
    }
  }

  /// One row per supplier that has at least one bill.
  Future<List<SupplierPayable>> fetchSummary() => _readAll(
    summaryPath,
    SupplierPayable.fromJson,
    'The payables summary could not be loaded.',
  );

  /// Records a payment (`{bill, amount, method, reference?, cheque_*?}`).
  ///
  /// [body] is built by the viewmodel, which owns the 2 dp money string: a
  /// double can serialize as `399.99999999999994` and the server would then
  /// refuse a payment nobody typed.
  Future<void> createPayment(Map<String, dynamic> body) async {
    try {
      await _client.post<dynamic>(paymentsPath, data: body);
    } on DioException catch (error) {
      throw PayablesServiceException(
        _message(error, 'The payment was refused.'),
      );
    }
  }

  Future<List<T>> _readAll<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson,
    String fallback, {
    Map<String, dynamic>? query,
  }) async {
    try {
      return await _client.getAll<T>(
        path,
        fromJson,
        queryParameters: query,
        maxPages: ApiClient.maxListPages,
      );
    } on DioException catch (error) {
      throw PayablesServiceException(_message(error, fallback));
    } on FormatException catch (error) {
      // A malformed row is a contract break, but it still has to reach the
      // screen as a retryable message instead of a blank table.
      throw PayablesServiceException('$fallback (${error.message})');
    } on TypeError {
      throw PayablesServiceException(
        '$fallback (a row was not the shape this app expects)',
      );
    }
  }

  String _message(DioException error, String fallback) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    final status = error.response?.statusCode;
    if (status == 401) return 'Your session has expired. Sign in again.';
    if (status == 403) {
      return 'No permission to view or record supplier payments.';
    }
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      // The server's sentence first: it names the bill and what is left to pay.
      final detail = data['detail'];
      if (detail is String && detail.trim().isNotEmpty) return detail;
      final code = data['code'];
      if (code is String) {
        final mapped = _codes[code];
        if (mapped != null) return mapped;
      }
      // A field-error dict (`{"cheque_number": ["..."]}`) is still a refusal a
      // clerk can act on, so it is read out rather than flattened to [fallback].
      for (final value in data.values) {
        if (value is List && value.isNotEmpty) return '${value.first}';
        if (value is String && value.isNotEmpty) return value;
      }
    }
    return fallback;
  }

  /// Fallback sentences for a code that arrived without a `detail`. The server
  /// always sends one; these exist so a bare code still says something a clerk
  /// can act on.
  static const Map<String, String> _codes = {
    'OVERPAYMENT':
        'That is more than the bill still owes. A payment cannot be larger '
        'than the balance.',
    'BILL_PAID': 'This bill is already paid in full.',
    'INVALID_SUPPLIER_PAYMENT':
        'That payment cannot be recorded. Check the amount and, for a cheque, '
        'its number, bank and date.',
  };
}
