import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/store_settings.dart';
import 'package:dio/dio.dart';

class StoreSettingsException implements Exception {
  const StoreSettingsException(
    this.message, {
    this.isForbidden = false,
    this.fieldErrors = const {},
  });

  /// A sentence for the user: what happened, and what to do next.
  final String message;

  /// True for a 403. The page shows the same banner either way; this lets a
  /// caller tell "you may not" apart from "that value is wrong".
  final bool isForbidden;

  /// Per-field sentences from a 400 (`{'vat_rate': ['…']}`), keyed by field
  /// name, for a form that wants to mark the field itself.
  final Map<String, String> fieldErrors;

  @override
  String toString() => message;
}

/// Reads and writes the store-wide settings (Phase 4 B1).
///
/// One endpoint does both: `GET /api/v1/store-settings/` answers any
/// authenticated user, `PATCH` the same path is Admin only server-side (403
/// otherwise) and answers 400 with field errors. Flutter never decides who may
/// write; it only shows the refusal the server sent.
class StoreSettingsService {
  StoreSettingsService({ApiClient? client})
    : _client = client ?? ApiClient.instance;

  static const String path = '/api/v1/store-settings/';

  final ApiClient _client;

  Future<StoreSettings> fetch() async {
    try {
      final response = await _client.dio.get<Map<String, dynamic>>(path);
      return _parse(response.data, 'Empty store settings response');
    } on DioException catch (error) {
      throw StoreSettingsException(
        _readError(error, 'The store settings could not be loaded.'),
        isForbidden: error.response?.statusCode == 403,
        fieldErrors: _fieldErrors(error),
      );
    } on FormatException catch (error) {
      throw StoreSettingsException(error.message);
    }
  }

  /// Stores [settings] and returns the row the server kept, not the one sent:
  /// the server owns rounding and `updated_at`.
  Future<StoreSettings> save(StoreSettings settings) async {
    try {
      final response = await _client.patch<Map<String, dynamic>>(
        path,
        data: settings.toPatchJson(),
      );
      return _parse(response.data, 'Empty store settings response');
    } on DioException catch (error) {
      throw StoreSettingsException(
        _readError(error, 'The store settings could not be saved.'),
        isForbidden: error.response?.statusCode == 403,
        fieldErrors: _fieldErrors(error),
      );
    } on FormatException catch (error) {
      throw StoreSettingsException(error.message);
    }
  }

  StoreSettings _parse(Map<String, dynamic>? data, String fallback) {
    if (data == null) throw FormatException(fallback);
    return StoreSettings.fromJson(data);
  }

  /// The server's own sentence, whatever the status.
  ///
  /// `detail` wins (the DRF error shape); otherwise the first field sentence
  /// stands in, so a 400 the client did not predict still reads as a refusal
  /// sentence instead of a generic one. Unknown codes are never swallowed.
  String _readError(DioException error, String fallback) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    if (error.response?.statusCode == 401) {
      return 'Your session has expired. Sign in again.';
    }
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
      for (final entry in data.values) {
        if (entry is List && entry.isNotEmpty && entry.first is String) {
          return entry.first as String;
        }
      }
    }
    if (error.response?.statusCode == 403) {
      return 'Only an Admin can change store settings.';
    }
    return fallback;
  }

  Map<String, String> _fieldErrors(DioException error) {
    final data = error.response?.data;
    if (data is! Map<String, dynamic> || error.response?.statusCode != 400) {
      return const {};
    }
    final errors = <String, String>{};
    for (final entry in data.entries) {
      final value = entry.value;
      if (value is List && value.isNotEmpty && value.first is String) {
        errors[entry.key] = value.first as String;
      }
    }
    return errors;
  }
}
