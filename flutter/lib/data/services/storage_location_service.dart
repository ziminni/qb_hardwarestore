import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:dio/dio.dart';

/// Raised when the storage-location list cannot be read or written. [message] is
/// safe to show.
class StorageLocationServiceException implements Exception {
  const StorageLocationServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// `GET/POST/PATCH /api/v1/storage-locations/` — the shop's pick-up points
/// (Phase 5 B4 wire, F4 screens; ENDPOINTS.md §3.3).
///
/// **Read for every signed-in role, write for Admin only.** A Cashier must be
/// able to resolve "Bodega" to print it; only an Admin decides the shop's places.
///
/// **No DELETE.** The route answers 405 — a location a product points at is
/// PROTECT-referenced, and the exit is `PATCH {"is_active": false}`. A
/// deactivated location keeps labelling the products already assigned to it.
///
/// A non-Admin read is the server's answer, not a client filter: it sends active
/// rows only, and an Admin also receives the deactivated ones (they are the only
/// role that can restore a place).
class StorageLocationService {
  StorageLocationService({ApiClient? client})
    : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const path = '/api/v1/storage-locations/';

  static const String _readFallback =
      'The storage locations could not be read.';

  /// Every location the caller may see, A→Z (the server's own order).
  ///
  /// `getAll` — not one DRF page: a shop with more than fifty places would hide
  /// the rest from the picker, so a product could not be filed under them.
  Future<List<StorageLocation>> fetchAll() async {
    try {
      return await _client.getAll<StorageLocation>(
        path,
        StorageLocation.fromJson,
      );
    } on DioException catch (error) {
      throw StorageLocationServiceException(_message(error, _readFallback));
    } on FormatException catch (error) {
      throw StorageLocationServiceException(
        '$_readFallback (${error.message})',
      );
    } on TypeError {
      throw StorageLocationServiceException(
        '$_readFallback (a row was not the shape this app expects)',
      );
    }
  }

  /// Creates a location by name and returns the saved row.
  Future<StorageLocation> create(String name) => _write(
    () => _client.post<Map<String, dynamic>>(path, data: {'name': name}),
  );

  /// Renames and/or deactivates a location. There is no DELETE on this route.
  Future<StorageLocation> patch(int id, {String? name, bool? isActive}) =>
      _write(
        () => _client.patch<Map<String, dynamic>>(
          '$path$id/',
          data: {'name': ?name, 'is_active': ?isActive},
        ),
      );

  Future<StorageLocation> _write(
    Future<Response<Map<String, dynamic>>> Function() write,
  ) async {
    try {
      final response = await write();
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('A storage location is a single object.');
      }
      return StorageLocation.fromJson(data);
    } on DioException catch (error) {
      throw StorageLocationServiceException(
        _message(error, 'The storage location could not be saved.'),
      );
    } on FormatException catch (error) {
      throw StorageLocationServiceException(
        'The storage location could not be read back. (${error.message})',
      );
    }
  }

  /// The server's own sentence first: `INVALID_STORAGE_LOCATION` on a product
  /// write names the location, and a duplicate name arrives as a DRF field error.
  String _message(DioException error, String fallback) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String && detail.trim().isNotEmpty) return detail;
      final code = data['code'];
      if (code is String && _codes.containsKey(code)) return _codes[code]!;
      for (final value in data.values) {
        if (value is List && value.isNotEmpty) return '${value.first}';
        if (value is String && value.isNotEmpty) return value;
      }
    }
    return switch (error.response?.statusCode) {
      401 => 'Your session has expired. Sign in again.',
      403 => 'Only an Admin can change the storage locations.',
      404 => 'That storage location no longer exists. Reload and try again.',
      405 => 'A storage location cannot be deleted: deactivate it instead.',
      _ => fallback,
    };
  }

  /// Only the code with no sentence of its own is rewritten here.
  static const Map<String, String> _codes = {
    'INVALID_STORAGE_LOCATION':
        'That storage location is not usable: pick an active one from the list.',
  };
}
