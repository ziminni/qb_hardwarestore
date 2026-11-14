// Phase 3 Task F2: the preview call.
//
// The server stays file-free (decision 23): this app parses the edited `.xlsx` and
// posts the rows as JSON. `POST /api/v1/catalogue-import/preview/` validates them
// against the existing serializers and answers what an apply WOULD do, writing
// nothing (backend task B1). `catalogue_import.COLUMNS` on the server names the
// row keys, so the map the sheet parser builds is the payload, unchanged.
//
// The same request will carry the apply later: B2 posts these rows back with the
// preview's fingerprint, which is why nothing here drops them.

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/catalogue_import_preview.dart';
import 'package:dio/dio.dart';

/// Raised for anything the import dialog must show a human. [message] is the
/// server's own sentence whenever the server sent one: it names the row, the
/// column and what to type instead, which this class cannot improve on.
class CatalogueImportServiceException implements Exception {
  const CatalogueImportServiceException(
    this.message, {
    this.errors = const [],
    this.isStale = false,
  });

  final String message;

  /// The rows the apply refused, in the preview's own shape (B2's 400
  /// `CATALOGUE_IMPORT_ROW_ERRORS`), so the dialog draws the same table. The rows
  /// are numbered over the rows this app SENT, not over the sheet.
  final List<CatalogueImportError> errors;

  /// The catalogue moved between the preview and the apply (409
  /// `CATALOGUE_PREVIEW_STALE`): nothing was written, and the rows have to be
  /// previewed again before they can be applied.
  final bool isStale;

  @override
  String toString() => message;
}

/// The catalogue import's server boundary.
class CatalogueImportService {
  CatalogueImportService({ApiClient? client})
    : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const previewPath = '/api/v1/catalogue-import/preview/';
  static const applyPath = '/api/v1/catalogue-import/apply/';

  /// What a preview that is no longer current is told to do (B2's
  /// `CATALOGUE_PREVIEW_STALE`): the catalogue moved since this preview, so the
  /// rows must be previewed again before anything is written.
  static const staleMessage = 'Run the preview again';

  /// Validates the rows and describes what an apply would change.
  Future<CatalogueImportPreview> preview(List<Map<String, String>> rows) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        previewPath,
        data: {'rows': rows},
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('The preview answer was not an object.');
      }
      return CatalogueImportPreview.fromJson(data);
    } on DioException catch (error) {
      throw CatalogueImportServiceException(_message(error));
    } on FormatException {
      throw const CatalogueImportServiceException(
        'The preview came back in a shape this app does not know. Reload and '
        'try again.',
      );
    }
  }

  /// Writes the previewed rows, or nothing (B2): the answer is what the apply
  /// DID. A fingerprint that no longer matches is refused as stale, and a sheet
  /// the catalogue moved under comes back with its row errors - both leave the
  /// catalogue untouched.
  Future<CatalogueImportApplied> apply(
    List<Map<String, String>> rows,
    String fingerprint,
  ) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        applyPath,
        data: {'rows': rows, 'fingerprint': fingerprint},
      );
      final data = response.data;
      if (data is! Map<String, dynamic>) {
        throw const FormatException('The apply answer was not an object.');
      }
      return CatalogueImportApplied.fromJson(data);
    } on DioException catch (error) {
      throw _applyFailure(error);
    } on FormatException {
      throw const CatalogueImportServiceException(
        'The apply came back in a shape this app does not know. Reload and try '
        'again.',
      );
    }
  }

  /// One apply refusal, with the two facts the dialog branches on: whether the
  /// catalogue moved (409, preview again) and the rows the server refused (400
  /// with `errors`), which it draws in the table the preview already uses.
  CatalogueImportServiceException _applyFailure(DioException error) {
    final data = error.response?.data;
    return CatalogueImportServiceException(
      _message(error),
      errors: _rowErrors(data is Map<String, dynamic> ? data['errors'] : null),
      isStale: error.response?.statusCode == 409,
    );
  }

  /// The apply's error list is the preview's own shape, so it is read by the same
  /// model: one `{row, column, code, message}` per refused cell.
  List<CatalogueImportError> _rowErrors(Object? value) => [
    if (value is List)
      for (final row in value.whereType<Map<String, dynamic>>())
        CatalogueImportError.fromJson(row),
  ];

  /// The visible sentence for one failure.
  ///
  /// The status comes first for the two answers that describe the CLERK rather
  /// than the file: a 403's own detail is Django's "You do not have permission",
  /// which says nothing a stock manager can act on.
  String _message(DioException error) {
    final status = error.response?.statusCode;
    if (status == 401) return 'Your session has expired. Sign in again.';
    if (status == 403) {
      return 'Only a stock manager, store manager or admin can import the '
          'catalogue.';
    }

    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final code = data['code'];
      if (code is String) {
        final mapped = _codes[code];
        if (mapped != null) return mapped;
      }
      // An unmapped code keeps the server's detail: it is the sentence written
      // for this exact refusal, so nothing here can say it better.
      final detail = data['detail'];
      if (detail is String && detail.isNotEmpty) return detail;
    }

    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    return switch (status) {
      404 => 'This server does not have the catalogue import yet.',
      _ => 'The catalogue import could not be read. Reload and try again.',
    };
  }

  /// The refusal codes worth wording here. Everything else is shown as the
  /// server wrote it, because every other refusal in this import is a ROW error
  /// the clerk fixes in Excel and the server names the cell.
  static const Map<String, String> _codes = {
    'CATALOGUE_PREVIEW_STALE': staleMessage,
  };
}
