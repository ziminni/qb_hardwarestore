import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/supplier_payables.dart';
import 'package:client/data/models/supplier_returns.dart';
import 'package:dio/dio.dart';

/// Raised when payables cannot be read or a payment is refused. [message] is
/// safe to show.
///
/// [code] is the server's stable token (`CHEQUE_ALREADY_DECIDED`,
/// `CHEQUE_REASON_REQUIRED`, `RETURN_EXCEEDS_RECEIPT`, …) so a screen can branch
/// on the fact while [message] stays the sentence written for a person.
class PayablesServiceException implements Exception {
  const PayablesServiceException(this.message, {this.code});

  final String message;
  final String? code;

  /// A second decision on a cheque that is already settled (409). The caller
  /// must re-read the queue: its rows are now wrong about this cheque.
  bool get alreadyDecided => code == 'CHEQUE_ALREADY_DECIDED';

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
  static const creditNotesPath = '/api/v1/supplier-credit-notes/';
  static const returnsPath = '/api/v1/supplier-returns/';
  static const receiptsPath = '/api/v1/goods-receipts/';

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
        code: _codeFor(error),
      );
    }
  }

  /// What one delivery can still give back, one row per receipt LINE and every
  /// quantity in that line's package unit (B2).
  ///
  /// This route answers a BARE ARRAY, not a page, so it cannot go through
  /// [ApiClient.getAll]: asking for pages here would throw a parse failure the
  /// clerk would read as "the server is broken".
  Future<List<SupplierReturnableLine>> fetchReturnable(int receiptId) async {
    try {
      final response = await _client.get<dynamic>(
        '$receiptsPath$receiptId/returnable/',
      );
      final body = response.data;
      if (body is! List) {
        throw const FormatException('A returnable report is a list of lines.');
      }
      return body
          .map(
            (row) =>
                SupplierReturnableLine.fromJson(row as Map<String, dynamic>),
          )
          .toList(growable: false);
    } on DioException catch (error) {
      throw PayablesServiceException(
        _message(error, 'The returnable quantities could not be loaded.'),
      );
    } on FormatException catch (error) {
      throw PayablesServiceException(
        'The returnable quantities could not be loaded. (${error.message})',
      );
    } on TypeError {
      throw const PayablesServiceException(
        'The returnable quantities could not be loaded. (a line was not the '
        'shape this app expects)',
      );
    }
  }

  /// Records a return (`{receipt, reason, lines: [{receipt_line, qty}]}`).
  ///
  /// [lines] carries the quantities exactly as the clerk typed them, as 2 dp
  /// strings: the server refuses a fraction of a whole package unit, and a
  /// double could send `2.0000000000000004`.
  ///
  /// The answer is the recorded return with its minted credit note, so the
  /// dialog can show the number, what it was worth and what is left as credit.
  Future<SupplierReturn> createReturn({
    required int receiptId,
    required String reason,
    required List<Map<String, dynamic>> lines,
  }) async {
    try {
      final response = await _client.post<dynamic>(
        returnsPath,
        data: {'receipt': receiptId, 'reason': reason.trim(), 'lines': lines},
      );
      final body = response.data;
      if (body is! Map<String, dynamic>) {
        throw const FormatException('A recorded return is a single object.');
      }
      return SupplierReturn.fromJson(body);
    } on DioException catch (error) {
      throw PayablesServiceException(
        _message(error, 'The return was refused.'),
        code: _codeFor(error),
      );
    } on FormatException catch (error) {
      // The return WAS written. Saying "refused" would invite a second one that
      // would move the same stock twice.
      throw PayablesServiceException(
        'The return was recorded but could not be read back. '
        'Reload before returning anything again. (${error.message})',
      );
    }
  }

  /// A supplier's credit notes, newest first (B4).
  ///
  /// [openOnly] is the "apply credit" picker: `?open=true` keeps only notes with
  /// money left, so the server decides what is spendable rather than the client
  /// filtering a page it happened to load.
  Future<List<SupplierCreditNote>> fetchCreditNotes({
    int? supplierId,
    bool openOnly = false,
  }) => _readAll(
    creditNotesPath,
    SupplierCreditNote.fromJson,
    'The supplier credit notes could not be loaded.',
    query: {'supplier': ?supplierId, if (openOnly) 'open': true},
  );

  /// The cheque queue: supplier payments, optionally one supplier's or one
  /// status's (B1), read from the same route the bills screen uses.
  ///
  /// [status] is the server's filter (`?status=ISSUED`), and an unknown code is
  /// its 400 rather than a silent empty list.
  Future<List<SupplierPayment>> fetchCheques({
    int? supplierId,
    SupplierPaymentStatus? status,
  }) => _readAll(
    paymentsPath,
    SupplierPayment.fromJson,
    'The supplier cheques could not be loaded.',
    query: {'supplier': ?supplierId, if (status != null) 'status': status.code},
  );

  /// The bank honoured a supplier cheque: nothing moves, the bill already
  /// counted it at issue. Returns the decided row.
  Future<SupplierPayment> clearCheque(int paymentId) =>
      _decideCheque(paymentId, 'clear');

  /// The bank refused it ([reason] required): the amount goes back on the bill.
  /// Returns the decided row.
  Future<SupplierPayment> bounceCheque(int paymentId, String reason) =>
      _decideCheque(paymentId, 'bounce', reason: reason);

  Future<SupplierPayment> _decideCheque(
    int paymentId,
    String action, {
    String? reason,
  }) async {
    try {
      final response = await _client.post<dynamic>(
        '$paymentsPath$paymentId/$action/',
        data: reason == null ? null : {'reason': reason.trim()},
      );
      final body = response.data;
      if (body is! Map<String, dynamic>) {
        throw const FormatException('A decided cheque is a single object.');
      }
      return SupplierPayment.fromJson(body);
    } on DioException catch (error) {
      throw PayablesServiceException(
        _message(error, 'The cheque decision was refused.'),
        code: _codeFor(error),
      );
    } on FormatException {
      // The decision went through but its answer is unreadable. Saying it was
      // refused would invite a second Clear on a cheque the server settled.
      throw const PayablesServiceException(
        'The decision was sent, but the cheque could not be read back. '
        'Reload before deciding again.',
      );
    }
  }

  String? _codeFor(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic> && data['code'] is String) {
      return data['code'] as String;
    }
    return null;
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
    if (status == 404) {
      return 'That supplier record no longer exists. Reload the list.';
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
