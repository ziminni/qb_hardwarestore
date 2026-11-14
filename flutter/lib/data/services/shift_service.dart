import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/shift.dart';
import 'package:dio/dio.dart';

/// Raised when the shift API cannot be reached or answers unexpectedly.
///
/// [message] is safe to show a cashier.
class ShiftServiceException implements Exception {
  const ShiftServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Cashier shifts and their Z-readings — Phase 4 of the cashier workflow.
///
/// A shift is the unit every sale is accounted for against: `process_sale`
/// attaches the cashier's open shift to each transaction and refuses the sale
/// when there is none (decision 06). Two consequences the caller must respect:
///
/// * **`fetchCurrent` returns null for "no open shift" and throws for "could
///   not ask".** Those are different answers, and the POS shell gates the till
///   on the difference: treating a failed request as "no shift" would let a
///   cashier open a second one.
/// * **Close is not retried blindly.** It is idempotent on the server (a second
///   close answers 400 `SHIFT_ALREADY_CLOSED`), so a timeout leaves a closed
///   shift behind and the Z-reading must be re-read, not re-posted.
class ShiftService {
  ShiftService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const shiftsPath = '/api/v1/shifts/';

  /// 10 x DRF's `PAGE_SIZE` (50) = 500 shifts, far past what one cashier
  /// accumulates. Hitting it means the API is misbehaving, not that the
  /// history is long.
  static const _maxPages = 10;

  /// The caller's open shift, or null when there is none.
  ///
  /// The server answers 404 for "no open shift" — the absence of the resource
  /// that was asked for — and that is the only status mapped to null.
  Future<Shift?> fetchCurrent() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '${shiftsPath}current/',
      );
      final data = response.data;
      if (data == null) {
        throw const ShiftServiceException(
          'The server did not return the current shift.',
        );
      }
      return Shift.fromJson(data);
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) return null;
      throw ShiftServiceException(_message(error));
    } on FormatException {
      throw const ShiftServiceException(
        'The current shift could not be read. Try again.',
      );
    }
  }

  /// Opens a shift with the counted cash in the drawer. The server rejects a
  /// second open shift for the same cashier with 400.
  Future<Shift> openShift(double openingFloat) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '${shiftsPath}open/',
        data: {'opening_float': openingFloat.toStringAsFixed(2)},
      );
      final data = response.data;
      if (data == null) {
        throw const ShiftServiceException(
          'The server did not return the opened shift.',
        );
      }
      return Shift.fromJson(data);
    } on DioException catch (error) {
      throw ShiftServiceException(_message(error));
    } on FormatException {
      throw const ShiftServiceException(
        'The server returned a shift this app cannot read.',
      );
    }
  }

  /// Closes the shift with the counted cash. The response carries the computed
  /// Z-reading. A non-zero variance is recorded, not refused.
  Future<Shift> closeShift(int shiftId, double closingCount) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '$shiftsPath$shiftId/close/',
        data: {'closing_count': closingCount.toStringAsFixed(2)},
      );
      final data = response.data;
      if (data == null) {
        throw const ShiftServiceException(
          'The server did not return the closed shift.',
        );
      }
      return Shift.fromJson(data);
    } on DioException catch (error) {
      throw ShiftServiceException(_message(error));
    } on FormatException {
      throw const ShiftServiceException(
        'The server returned a shift this app cannot read.',
      );
    }
  }

  /// The caller's shifts, newest first (the model's ordering). A cashier sees
  /// their own; a manager sees everyone's — the server decides which.
  Future<List<Shift>> fetchAll() async {
    try {
      final all = <Shift>[];
      var page = 1;
      while (true) {
        final result = await _client.getList<Shift>(
          shiftsPath,
          Shift.fromJson,
          queryParameters: {'page': page},
        );
        all.addAll(result.items);
        if (!result.hasMore) return all;
        page++;
        if (page > _maxPages) {
          throw const FormatException('The shift list did not end.');
        }
      }
    } on DioException catch (error) {
      throw ShiftServiceException(_message(error));
    } on FormatException {
      throw const ShiftServiceException(
        'The shifts could not be read. Try again.',
      );
    }
  }

  /// Maps a transport failure onto something a cashier can act on. The server's
  /// own `detail` wins when present: `SHIFT_ALREADY_OPEN` says what to do next,
  /// where a generic message would not.
  String _message(DioException error) {
    final body = error.response?.data;
    if (body is Map<String, dynamic>) {
      final detail = body['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    }
    switch (error.type) {
      case DioExceptionType.connectionError:
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Cannot connect to the BuildPro server.';
      default:
        return 'The shift could not be loaded. Try again.';
    }
  }
}
