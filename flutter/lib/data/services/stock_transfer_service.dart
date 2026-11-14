import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/stock_transfer.dart';
import 'package:dio/dio.dart';

/// Raised when a transfer cannot be read or recorded. [message] is safe to show.
///
/// [code] is the server's own stable code (`INSUFFICIENT_STOCK`,
/// `INVALID_STORAGE_LOCATION`, …) and [shortfall] its figure, when it sent one,
/// so the dialog can say WHICH rule refused the slip instead of only "refused".
class StockTransferServiceException implements Exception {
  const StockTransferServiceException(
    this.message, {
    this.code,
    this.shortfall,
  });

  final String message;
  final String? code;
  final double? shortfall;

  @override
  String toString() => message;
}

/// `GET/POST /api/v1/stock-transfers/` — one-step numbered moves between shelves
/// (Phase 9 B4 wire, F3 screens; ENDPOINTS.md §3.3).
///
/// **Append-only.** The route answers 405 to PUT/PATCH/DELETE for every role, so
/// there is no writer here beyond [create]: a mistake is a transfer back, not an
/// edit. The slip the server numbers in [create] is the record.
class StockTransferService {
  StockTransferService({ApiClient? client})
    : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const path = '/api/v1/stock-transfers/';

  static const String _readFallback = 'The stock transfers could not be read.';
  static const String _writeFallback =
      'The stock transfer could not be recorded.';

  /// Every recorded transfer, newest first (the server's own order).
  ///
  /// `getAll` — the route is paginated at 50/page, and a shelf move from last
  /// week is exactly what a reader scrolls back for. One page would hide it.
  Future<List<StockTransfer>> fetchAll() async {
    try {
      return await _client.getAll<StockTransfer>(
        path,
        StockTransfer.fromJson,
      );
    } on DioException catch (error) {
      throw _failure(error, _readFallback);
    } on FormatException catch (error) {
      throw StockTransferServiceException(
        '$_readFallback (${error.message})',
      );
    } on TypeError {
      throw StockTransferServiceException(
        '$_readFallback (a row was not the shape this app expects)',
      );
    }
  }

  /// Records a transfer and returns the server's numbered slip.
  ///
  /// Nothing is converted or validated here: the body carries the selling unit
  /// the clerk counted in and the server converts it to base stock, refusing a
  /// fraction it cannot store. A refusal arrives as [StockTransferServiceException]
  /// with the server's own sentence and code, which is what the dialog shows.
  Future<StockTransfer> create(StockTransferRequest request) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        path,
        data: request.toJson(),
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('A transfer is a single object.');
      }
      return StockTransfer.fromJson(data);
    } on DioException catch (error) {
      throw _failure(error, _writeFallback);
    } on FormatException catch (error) {
      throw StockTransferServiceException(
        'The transfer was recorded but its slip could not be read back. '
        '(${error.message})',
      );
    } on TypeError {
      throw StockTransferServiceException(
        'The transfer was recorded but its slip could not be read back.',
      );
    }
  }

  /// The server's own sentence first: every transfer refusal carries a `detail`
  /// naming the shelf, the unit or the shortfall, and a canned sentence could
  /// only say less. [StockTransferServiceException.code] and `shortfall` are
  /// kept so a caller can branch without parsing prose.
  StockTransferServiceException _failure(
    DioException error,
    String fallback,
  ) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return const StockTransferServiceException(
        'Cannot connect to the BuildPro server.',
      );
    }
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final code = data['code'];
      final shortfall = data['shortfall'];
      final detail = data['detail'];
      final message = detail is String && detail.trim().isNotEmpty
          ? detail
          : (code is String ? _codes[code] : null);
      if (message != null) {
        return StockTransferServiceException(
          message,
          code: code is String ? code : null,
          shortfall: shortfall == null ? null : double.tryParse('$shortfall'),
        );
      }
      for (final value in data.values) {
        if (value is List && value.isNotEmpty) {
          return StockTransferServiceException('${value.first}');
        }
        if (value is String && value.isNotEmpty) {
          return StockTransferServiceException(value);
        }
      }
    }
    return StockTransferServiceException(switch (error.response?.statusCode) {
      401 => 'Your session has expired. Sign in again.',
      403 =>
        'Only a Stock Manager, Store Manager or Admin can move stock '
            'between shelves.',
      404 => 'That shelf no longer exists. Reload and try again.',
      405 =>
        'A recorded transfer cannot be changed: record the move back '
            'instead.',
      _ => fallback,
    });
  }

  /// Only the codes whose sentence the client has to invent are listed: every
  /// rule the server phrases itself arrives as `detail` and is shown untouched.
  static const Map<String, String> _codes = {
    'INSUFFICIENT_STOCK':
        'There is not enough stock on the source shelf for this transfer.',
    'INVALID_STORAGE_LOCATION':
        'These shelves cannot be used: pick two different active shelves.',
    'INACTIVE_SELLING_UNIT':
        'That product or unit is archived and cannot be moved.',
    'WHOLE_UNIT_QUANTITY':
        'This unit is counted in whole pieces: enter a whole quantity.',
    'TRANSFER_QUANTITY_UNREPRESENTABLE':
        'That quantity converts to a fraction of a base unit smaller than '
        '0.01, which stock cannot hold. Transfer a whole 0.01 of the base unit.',
  };
}
