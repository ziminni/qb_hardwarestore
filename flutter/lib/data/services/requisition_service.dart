import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/paged.dart';
import 'package:client/data/models/requisition.dart';
import 'package:dio/dio.dart';

/// Raised for anything the requisition screens must show to a human.
///
/// It carries the SERVER's prose whenever the server sent any. The lifecycle guards refuse an
/// illegal transition with a specific reason ("Cannot approve a DRAFT requisition."), and
/// replacing that with a generic message throws away the only explanation the manager gets for a
/// button that did nothing.
class RequisitionServiceException implements Exception {
  const RequisitionServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The POS half of the requisition lifecycle (decision 09, locked 2026-10-17).
///
/// Approve · reject · verify token · release. Create and submit are deliberately ABSENT: they need
/// a Site Foreman, which is a CPMS identity that never logs into POS, so building them here would
/// duplicate CPMS and demand a role this client does not have.
class RequisitionService {
  RequisitionService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const String requisitionsPath = '/api/v1/requisitions/';
  static const String verifyPath = '/api/v1/tokens/verify/';
  static const String releasePath = '/api/v1/tokens/release/';

  /// The server's page size; the bound below is expressed in those units.
  static const int _maxPages = 40;

  /// Every requisition, following pagination.
  ///
  /// Follows the pages for the same reason the customer picker and the receivables screen do: a
  /// queue that silently stops at the 50th request is a queue that loses material.
  Future<List<Requisition>> fetchRequisitions() async {
    final all = <Requisition>[];
    var page = 1;
    while (page <= _maxPages) {
      final Paged<Requisition> response;
      try {
        response = await _client.getList<Requisition>(
          requisitionsPath,
          Requisition.fromJson,
          queryParameters: {'page': page},
        );
      } on DioException catch (error) {
        throw RequisitionServiceException(_messageFor(error));
      } on FormatException {
        throw const RequisitionServiceException(
          'The requisition data could not be read. Try again.',
        );
      }
      all.addAll(response.items);
      if (!response.hasMore) return all;
      page++;
    }
    throw const RequisitionServiceException(
      'The requisition list did not finish loading. Try again.',
    );
  }

  /// Approves a SUBMITTED requisition and returns the token the server minted.
  ///
  /// The token is generated server-side inside the approval transaction, so this returns it
  /// rather than expecting the caller to re-read the requisition.
  Future<String> approve(int requisitionId) async {
    final body = await _post('$requisitionsPath$requisitionId/approve/');
    final token = body['token'] as String?;
    if (token == null) {
      // Approval succeeded but no token came back, which means the cashier cannot release the
      // material. Failing loudly beats showing a success the counter cannot act on.
      throw const RequisitionServiceException(
        'The requisition was approved but no release token was returned. Try again.',
      );
    }
    return token;
  }

  /// Rejects a SUBMITTED requisition.
  Future<void> reject(int requisitionId) async {
    await _post('$requisitionsPath$requisitionId/reject/');
  }

  /// Verifies a token and returns what it is for. Moves NOTHING.
  Future<TokenVerification> verifyToken(String token) async {
    final body = await _post(verifyPath, {'token': token});
    return _decode(TokenVerification.fromJson, body);
  }

  /// Releases the materials a token authorises.
  ///
  /// This is the only irreversible action in Phase 5: it FIFO-deducts stock, creates a sale and
  /// posts a receivable. The server re-checks the token under `select_for_update`, so a token
  /// used twice is refused rather than double-released.
  Future<ReleaseResult> release(String token) async {
    final body = await _post(releasePath, {'token': token});
    return _decode(ReleaseResult.fromJson, body);
  }

  /// POSTs [body] and returns the decoded object.
  ///
  /// A server message wins whenever there is one, because the requisition guards explain
  /// themselves better than any generic wording could.
  Future<Map<String, dynamic>> _post(
    String path, [
    Map<String, dynamic> body = const {},
  ]) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(path, data: body);
      final data = response.data;
      if (data == null) {
        throw const RequisitionServiceException(
          'The server returned an empty response.',
        );
      }
      return data;
    } on DioException catch (error) {
      throw RequisitionServiceException(_messageFor(error));
    } on FormatException {
      throw const RequisitionServiceException(
        'The requisition data could not be read. Try again.',
      );
    }
  }

  /// Maps a decoded body, turning a DRIFTED shape into words a clerk can act on.
  ///
  /// The parsers used to run OUTSIDE the guarded conversion, so a 200 whose shape moved threw a bare
  /// `FormatException`. `verify` swallowed it silently (no error, nothing on screen) and `release`
  /// propagated it out of the button callback - leaving the one irreversible screen on its spinner.
  T _decode<T>(T Function(Map<String, dynamic> json) parse, Map<String, dynamic> body) {
    try {
      return parse(body);
    } on FormatException {
      throw const RequisitionServiceException(
        'The server sent an unexpected response. Try again.',
      );
    }
  }

  String _messageFor(DioException error) {
    if (_serverCode(error) == 'NO_BASE_UOM') {
      // Phase 1 Task 5: `release_materials` refuses a variant with no
      // conversion-factor-1 selling unit BEFORE any write, because the old fallback
      // priced it at zero and killed the sale halfway through. A clerk needs the
      // instruction that unblocks the counter, not 'The requisitions could not be
      // loaded.' — so the server's own detail is kept, prefixed with what it means.
      const intro =
          'The release was refused: this material has no base unit in the '
          'catalogue.';
      final detail = _serverDetail(error);
      return detail == null ? intro : '$intro $detail';
    }
    final detail = _serverDetail(error);
    if (detail != null) return detail;
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    final status = error.response?.statusCode;
    if (status == 401) return 'Your session has expired. Sign in again.';
    if (status == 403) return 'You do not have access to requisitions.';
    return 'The requisitions could not be loaded.';
  }

  /// The stable machine-readable `code` a business-rule refusal carries, if any.
  String? _serverCode(DioException error) {
    final data = error.response?.data;
    if (data is! Map) return null;
    final code = data['code'];
    return code is String ? code : null;
  }

  /// The `detail` string a DRF error response carries, when it sent one.
  String? _serverDetail(DioException error) {
    final data = error.response?.data;
    if (data is! Map) return null;
    if (data['detail'] is String) return data['detail'] as String;
    // A DRF FIELD error carries no `detail` at all: a non-UUID token comes back as
    // {'token': ['Enter a valid UUID.']}, so returning null here told a clerk who mistyped a token
    // that the REQUISITIONS had failed to load. The first field message is far closer to the truth.
    for (final value in data.values) {
      if (value is List && value.isNotEmpty && value.first is String) {
        return value.first as String;
      }
      if (value is String) return value;
    }
    return null;
  }
}
