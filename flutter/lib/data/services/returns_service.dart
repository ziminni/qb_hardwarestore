import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/returns.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:dio/dio.dart';

/// A refusal or failure a cashier must be able to read.
///
/// [code] is the server's stable machine-readable code when it sent one, which
/// is what lets the screen tell a RULE ("open a shift first") apart from a
/// FAILURE ("the server did not answer"). Two callers depend on it: the page's
/// "Go to Shifts" button and the `returnable/` pre-flight wording.
class ReturnsServiceException implements Exception {
  const ReturnsServiceException(
    this.message, {
    this.code,
    this.needsOpenShift = false,
  });

  final String message;
  final String? code;

  /// True only for `NO_OPEN_SHIFT`: the one refusal with a next step the screen
  /// can take on the cashier's behalf.
  final bool needsOpenShift;

  @override
  String toString() => message;
}

/// The till's returns endpoints (decision 05, Phase 3).
///
/// The flow is search -> pre-flight -> POST, and each step exists for a reason:
///
/// * **Search** is `GET /transactions/?q=`, a case-insensitive EXACT match on the
///   transaction number or the receipt's OR number, applied AFTER the cashier
///   scope. Another till's number therefore answers an EMPTY page, not a 403:
///   "hidden, not forbidden" is the server's rule, and this client must not turn
///   an empty page into a hint that the sale exists.
/// * **Pre-flight** is `GET /transactions/{id}/returnable/`: what is left per
///   selling unit and what utang the sale still owes. The screen shows those
///   numbers rather than guessing, so a "70 left" that the server would refuse
///   cannot happen.
/// * **POST** carries `source: 'RETURN'`, the ORIGINAL sale (and its customer),
///   the reason, the refund method, and qty per **VariantUOM** id. Prices,
///   restock, ledger settlement and the refund summary are all the server's.
class ReturnsService {
  ReturnsService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const String transactionsPath = '/api/v1/transactions/';

  /// Finds the sale the customer is holding a slip for.
  ///
  /// Null means "no sale of yours matches" — a miss is an ordinary answer, not a
  /// failure, so it is not an exception. A malformed body still throws
  /// (through [TransactionRecord.fromJson]) because that IS a contract break.
  Future<TransactionRecord?> findSale(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return null;
    try {
      final page = await _client.getList<TransactionRecord>(
        transactionsPath,
        TransactionRecord.fromJson,
        queryParameters: {'q': trimmed},
      );
      return page.items.isEmpty ? null : page.items.first;
    } on DioException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const ReturnsServiceException(
        'That sale was found but could not be read. Tell a supervisor.',
      );
    }
  }

  /// What the server says is left to return on [transactionId].
  ///
  /// A 404 here means the sale is not this cashier's (the endpoint resolves
  /// through the caller's scoped queryset), which is deliberately
  /// indistinguishable from "no such sale" — so neither does this message.
  Future<ReturnableSale> fetchReturnable(int transactionId) async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '$transactionsPath$transactionId/returnable/',
      );
      final data = response.data;
      if (data == null) {
        throw const ReturnsServiceException(
          'The server did not say what can be returned.',
        );
      }
      return ReturnableSale.fromJson(data);
    } on DioException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const ReturnsServiceException(
        'The returnable quantities could not be read. Tell a supervisor.',
      );
    }
  }

  /// Posts the return and returns its number plus the refund summary.
  ///
  /// The customer is the ORIGINAL sale's customer: a refund against someone
  /// else's sale would settle the wrong person's utang.
  Future<ReturnResult> postReturn({
    required int customerId,
    required int originalTransactionId,
    required String reason,
    required String paymentMethod,
    required List<ReturnRequestLine> lines,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        transactionsPath,
        data: {
          'customer': customerId,
          'source': 'RETURN',
          'original_transaction': originalTransactionId,
          'reason': reason.trim(),
          'payment_method': paymentMethod,
          'items': [for (final line in lines) line.toJson()],
        },
      );
      final data = response.data;
      if (data == null) {
        throw const ReturnsServiceException(
          'The server did not return the refund summary.',
        );
      }
      return ReturnResult.fromJson(data);
    } on DioException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      // The return may well have been written. Saying so is what stops a
      // cashier re-posting it and refunding twice.
      throw const ReturnsServiceException(
        'The return was sent but its refund summary could not be read. Check '
        'the transaction history before trying again.',
      );
    }
  }

  /// Posts a manager-only return with no original sale (Phase 5).
  ///
  /// Same wire shape as [postReturn] minus `original_transaction`: the server
  /// treats an absent key as unlinked, prices lines at the selling units'
  /// `default_selling_price`, and 403s non-managers with
  /// `UNLINKED_RETURN_FORBIDDEN` itself. The customer is chosen in the
  /// dialog because there is no original sale to inherit one from.
  Future<ReturnResult> postUnlinkedReturn({
    required int customerId,
    required String reason,
    required String paymentMethod,
    required List<ReturnRequestLine> lines,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        transactionsPath,
        data: {
          'customer': customerId,
          'source': 'RETURN',
          'reason': reason.trim(),
          'payment_method': paymentMethod,
          'items': [for (final line in lines) line.toJson()],
        },
      );
      final data = response.data;
      if (data == null) {
        throw const ReturnsServiceException(
          'The server did not return the refund summary.',
        );
      }
      return ReturnResult.fromJson(data);
    } on DioException catch (error) {
      throw _failureFor(error);
    } on FormatException {
      throw const ReturnsServiceException(
        'The return was sent but its refund summary could not be read. Check '
        'the transaction history before trying again.',
      );
    }
  }

  /// Maps a transport failure onto something a cashier can act on.
  ///
  /// Order matters, and 404 comes SECOND (after a stable code) even though it
  /// carries a `detail`: DRF's `{"detail": "Not found."}` is true and useless at
  /// a counter, where the cashier needs to know that the number on the slip is
  /// either mistyped or another till's sale — the server deliberately makes
  /// those two indistinguishable.
  ReturnsServiceException _failureFor(DioException error) {
    final response = error.response;
    final body = response?.data;
    final code = body is Map && body['code'] is String
        ? body['code'] as String
        : null;
    final detail = _detailOf(body);

    if (code != null) {
      final intro = returnMessageFor(code);
      if (code == 'RETURN_QTY_EXCEEDED') {
        return ReturnsServiceException(
          _qtyExceededMessage(body, intro),
          code: code,
        );
      }
      if (intro != null) {
        return ReturnsServiceException(
          detail == null ? intro : '$intro $detail',
          code: code,
          needsOpenShift: code == 'NO_OPEN_SHIFT',
        );
      }
      return ReturnsServiceException(
        detail ?? 'The return was refused ($code).',
        code: code,
      );
    }

    final status = response?.statusCode;
    if (status == 404) {
      return const ReturnsServiceException(
        'No sale of yours matches that number. Check the receipt with the '
        'customer.',
        code: 'NOT_FOUND',
      );
    }
    if (detail != null) return ReturnsServiceException(detail);

    if (status == 401) {
      return const ReturnsServiceException(
        'Your session has expired. Sign in again.',
      );
    }
    if (status == 403) {
      return const ReturnsServiceException(
        'You do not have access to returns.',
      );
    }
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return const ReturnsServiceException(
          'Cannot connect to the BuildPro server.',
        );
      default:
        return const ReturnsServiceException(
          'The return could not be completed. Try again.',
        );
    }
  }

  /// `RETURN_QTY_EXCEEDED` arrives with four numbers and no prose worth
  /// printing, so the instruction is assembled here: which selling unit, how
  /// much was sold, how much already came back, and how much was asked for.
  String _qtyExceededMessage(Object? body, String? intro) {
    if (body is! Map) return intro ?? 'That is more than is left to return.';
    final sold = body['sold'];
    final already = body['already_returned'];
    final requested = body['requested'];
    final variant = body['variant_uom'];
    if (sold == null || already == null || requested == null) {
      return intro ?? 'That is more than is left to return.';
    }
    return 'Selling unit $variant sold $sold on this sale, $already already '
        'returned, and $requested is being asked for.';
  }

  /// The `detail` string a DRF error body carries, when it sent one.
  static String? _detailOf(Object? body) {
    if (body is! Map) return null;
    final detail = body['detail'];
    if (detail is String && detail.isNotEmpty) return detail;
    // A DRF FIELD error has no `detail` at all — `{'reason': ['This field is
    // required.']}` — and those words are closer to the truth than a generic one.
    for (final value in body.values) {
      if (value is List && value.isNotEmpty && value.first is String) {
        return value.first as String;
      }
      if (value is String && value.isNotEmpty) return value;
    }
    return null;
  }
}
