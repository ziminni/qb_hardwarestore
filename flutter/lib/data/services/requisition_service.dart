import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/paged.dart';
import 'package:client/data/models/requisition.dart';
import 'package:dio/dio.dart';

/// Raised for anything the release screens must show to a human.
///
/// It carries the SERVER's prose whenever the server sent any: a release refused for stock or
/// for a closed request explains itself far better than any generic wording could, and replacing
/// that prose with "something went wrong" throws away the only explanation the clerk gets.
class RequisitionServiceException implements Exception {
  const RequisitionServiceException(this.message, {this.code});

  final String message;

  /// The server's stable machine-readable code, when it sent one.
  ///
  /// Phase 3 Task 4 needs it for exactly one refusal: `NO_OPEN_SHIFT` is the
  /// only release failure with a NEXT STEP the screen can take (open a shift),
  /// and a transport failure that merely mentions "shift" in prose would be a
  /// guess.
  final String? code;

  @override
  String toString() => message;
}

/// The POS's read on approved requisitions, plus the two token calls (decision 01, locked
/// 2026-11-03).
///
/// Read · verify token · release. Create, submit, approve and reject are deliberately ABSENT:
/// requests are made and approved in CPMS by people who never log into the POS, so a client-side
/// write here would duplicate CPMS and demand a role this client does not have.
class RequisitionService {
  RequisitionService({ApiClient? client})
    : _client = client ?? ApiClient.instance;

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
        throw RequisitionServiceException(
          _messageFor(error),
          code: _serverCode(error),
        );
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
      final response = await _client.post<Map<String, dynamic>>(
        path,
        data: body,
      );
      final data = response.data;
      if (data == null) {
        throw const RequisitionServiceException(
          'The server returned an empty response.',
        );
      }
      return data;
    } on DioException catch (error) {
      // The CODE travels with the message (Phase 3 Task 4): `NO_OPEN_SHIFT` is
      // the one release refusal the screen can FIX, and only the code says so.
      throw RequisitionServiceException(
        _messageFor(error),
        code: _serverCode(error),
      );
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
  T _decode<T>(
    T Function(Map<String, dynamic> json) parse,
    Map<String, dynamic> body,
  ) {
    try {
      return parse(body);
    } on FormatException {
      throw const RequisitionServiceException(
        'The server sent an unexpected response. Try again.',
      );
    }
  }

  String _messageFor(DioException error) {
    final code = _serverCode(error);
    // Phase 1 Task 9 (decision 05): a FACT about the shelf or the request, in words a
    // clerk can act on. The server's detail is written for a developer.
    if (_plainCopy[code] case final copy?) return copy;
    if (_statusRefusalCopy[code] case final copy?) return copy;
    if (_ruleIntros[code] case final intro?) {
      // Phase 2 Tasks 3/7: these two refusals are RULES, not failures, and they are the whole
      // reason a manager's Approve button does nothing. The server's detail already explains it,
      // so it is kept — but the code names the rule even when the body lost its detail, which
      // is what stops a refusal degrading to 'The requisitions could not be loaded.'
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

  /// What each business-rule `code` means, in words a clerk can act on.
  ///
  /// Keyed by the stable codes from ENDPOINTS.md §3.6, so a new rule is one line here instead of
  /// another branch inside [_messageFor]. Only codes the POS can still RECEIVE belong here: the
  /// approval-era ones (SELF_APPROVAL, REQUISITION_LOCKED) went with the approve/reject actions
  /// (decision 01), and NO_BASE_UOM went with the pricing fallback it guarded (Phase 1 Task 5).
  static const Map<String, String> _ruleIntros = {
    // Decision 03 (Phase 3 Task 1): a release now writes a SalesTransaction
    // against the cashier's open shift, so the Z-reading counts it in the
    // transaction count and gross sales. No shift, no release.
    'NO_OPEN_SHIFT':
        'Open a shift before releasing materials. A release is recorded '
        'against a shift, so the Z-reading counts it in the day\'s sales.',
  };

  /// Refusals the till answers with its OWN words, replacing the server's detail.
  ///
  /// Both are FACTS rather than failures. `NOTHING_TO_RELEASE` writes nothing and leaves
  /// the token valid, and the three dead-end statuses are decisions made in CPMS — so a
  /// clerk gets an instruction, not a sentence about rows and dead tokens (decision 05).
  static const Map<String, String> _plainCopy = {
    'NOTHING_TO_RELEASE':
        'Nothing on this request is in stock right now. Try the same token again '
        'after the next delivery.',
  };

  /// The dead-end statuses, in the clerk's words.
  ///
  /// A CLOSED request is the project's decision made somewhere else, so the only useful
  /// next step is asking the project for a new one.
  static const Map<String, String> _statusRefusalCopy = {
    'REQUISITION_CLOSED':
        'This request was closed in the project system. Ask the project to send a '
        'new one.',
    'REQUISITION_RELEASED':
        'Everything on this request was already released. There is nothing left to '
        'hand over.',
    'REQUISITION_CANCELLED':
        'This request was cancelled in the project system, so nothing can be '
        'released for it.',
  };

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
