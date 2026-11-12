import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:dio/dio.dart';

/// Raised for anything a sales screen must show to a human.
class SalesServiceException implements Exception {
  const SalesServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads the live sales documents — transactions, quotations, orders.
///
/// Decision 05: quotations and orders got real backends in Phase 6, so the
/// sales role's seven screens stop reading mock viewmodels and read these
/// endpoints instead. Lists follow pagination like every other list reader.
class SalesService {
  SalesService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const String transactionsPath = '/api/v1/transactions/';
  static const String quotationsPath = '/api/v1/quotations/';
  static const String salesOrdersPath = '/api/v1/sales-orders/';

  /// Page size the server is configured with; the bound below is expressed in
  /// those units.
  static const int _maxPages = 40;

  /// Every sales transaction, optionally narrowed by source (`RETURN` powers
  /// the returns page — decision 15's amendment wires it over this endpoint).
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async {
    final rows = <TransactionRecord>[];
    var page = 1;
    while (page <= _maxPages) {
      final response = await _guard(
        () => _client.getList<TransactionRecord>(
          transactionsPath,
          TransactionRecord.fromJson,
          queryParameters: {'source': ?source, 'page': page},
        ),
        'sales transactions',
      );
      rows.addAll(response.items);
      if (!response.hasMore) return rows;
      page++;
    }
    throw const SalesServiceException(
      'The sales list did not finish loading. Try again.',
    );
  }

  /// Every quotation with its lines.
  Future<List<QuotationRecord>> fetchQuotations() async {
    final rows = <QuotationRecord>[];
    var page = 1;
    while (page <= _maxPages) {
      final response = await _guard(
        () => _client.getList<QuotationRecord>(
          quotationsPath,
          QuotationRecord.fromJson,
          queryParameters: {'page': page},
        ),
        'quotations',
      );
      rows.addAll(response.items);
      if (!response.hasMore) return rows;
      page++;
    }
    throw const SalesServiceException(
      'The quotation list did not finish loading. Try again.',
    );
  }

  /// Every sales order.
  Future<List<SalesOrderRow>> fetchSalesOrders() async {
    final rows = <SalesOrderRow>[];
    var page = 1;
    while (page <= _maxPages) {
      final response = await _guard(
        () => _client.getList<SalesOrderRow>(
          salesOrdersPath,
          SalesOrderRow.fromJson,
          queryParameters: {'page': page},
        ),
        'sales orders',
      );
      rows.addAll(response.items);
      if (!response.hasMore) return rows;
      page++;
    }
    throw const SalesServiceException(
      'The order list did not finish loading. Try again.',
    );
  }

  /// Creates ONE sales order and returns the server's row.
  ///
  /// Phase 5 F3 follow-up: the owner authorised CREATE-ONLY entry. There is no
  /// update, delete, status or fulfil route on this client, so this is the only
  /// write a sales order has.
  ///
  /// A refusal is re-thrown as the server's own sentence (a `WHOLE_UNIT_QUANTITY`
  /// detail names the line and the unit; an `INVALID_DELIVERY` detail names the
  /// field), because the form keeps the clerk's input on screen and needs to say
  /// which of those went wrong. A body without an order is a FAILURE, never a
  /// silent success: the screen would otherwise list an order nobody wrote.
  Future<SalesOrderRow> createSalesOrder(SalesOrderDraft draft) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        salesOrdersPath,
        data: draft.toJson(),
      );
      final data = response.data;
      if (data == null) {
        throw const SalesServiceException(
          'The server did not return the saved sales order.',
        );
      }
      return SalesOrderRow.fromJson(data);
    } on DioException catch (error) {
      throw SalesServiceException(_refusal(error));
    }
  }

  /// Why a create was refused, in words a clerk can act on.
  ///
  /// The server's `detail` comes first — it names the line, or the delivery field
  /// that is missing — and the coded fallbacks exist only for a body that arrived
  /// without one.
  String _refusal(DioException error) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    final status = error.response?.statusCode;
    if (status == 401) return 'Your session has expired. Sign in again.';
    if (status == 403) {
      return 'You do not have permission to create a sales order.';
    }
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String && detail.trim().isNotEmpty) return detail;
      final code = data['code'];
      if (code is String) {
        final mapped = _refusalCodes[code];
        if (mapped != null) return mapped;
      }
      // A field-error dict (`{"items": ["..."]}`) is still an answer a clerk can
      // act on, so it is read out rather than flattened to the fallback.
      for (final value in data.values) {
        if (value is List && value.isNotEmpty) return '${value.first}';
        if (value is String && value.isNotEmpty) return value;
      }
    }
    return 'The sales order was refused. Nothing was saved.';
  }

  /// Fallback sentences for a code that arrived without a `detail`.
  static const Map<String, String> _refusalCodes = {
    'WHOLE_UNIT_QUANTITY':
        'That unit is sold in whole numbers, so the quantity must be a whole '
        'number. Change it and try again.',
    'INVALID_DELIVERY':
        'That delivery cannot be saved. Check the address, the contact and the '
        'scheduled date.',
  };

  /// Runs a read, converting a transport failure into a message worth showing.
  ///
  /// Deliberately does NOT catch `FormatException`: a malformed body is a
  /// contract break and must fail loudly rather than be reported as a network
  /// problem the cashier could retry their way out of.
  Future<T> _guard<T>(Future<T> Function() read, String what) async {
    try {
      return await read();
    } on DioException catch (error) {
      throw SalesServiceException(_message(error, what));
    }
  }

  String _message(DioException error, String what) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    final status = error.response?.statusCode;
    if (status == 401) return 'Your session has expired. Sign in again.';
    if (status == 403) return 'You do not have access to $what.';
    return 'The $what could not be loaded.';
  }
}
