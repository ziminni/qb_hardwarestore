import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/requisition.dart';
import 'package:dio/dio.dart';

/// Raised for anything the release screens must show to a human.
///
/// It carries the SERVER's prose whenever the server sent any: a release refused for stock or
/// for a closed request explains itself far better than any generic wording could, and replacing
/// that prose with "something went wrong" throws away the only explanation the clerk gets.
class RequisitionServiceException implements Exception {
  const RequisitionServiceException(
    this.message, {
    this.code,
    this.outcomeUnknown = false,
  });

  final String message;

  /// The server's stable machine-readable code, when it sent one.
  ///
  /// Phase 3 Task 4 needs it for exactly one refusal: `NO_OPEN_SHIFT` is the
  /// only release failure with a NEXT STEP the screen can take (open a shift),
  /// and a transport failure that merely mentions "shift" in prose would be a
  /// guess. Phase 1b adds `REQUEST_ALREADY_REVIEWED`, the stale-decision answer.
  final String? code;

  /// True when a WRITE was sent and no HTTP answer came back: a timeout, or the connection
  /// dropped after the request left this machine.
  ///
  /// The decision may or may not have been stored, so the screen must RELOAD before it lets
  /// anyone press Accept or Decline again. A resubmit on a decision that did land is a
  /// second answer to a request that already has one.
  final bool outcomeUnknown;

  @override
  String toString() => message;
}

/// The POS's read on project requests, the store's answer to them, and the two token calls
/// (decisions 01, 09 and 10).
///
/// Read · answer (accept/decline) · verify token · release. Create, submit, approve and
/// reject stay ABSENT: those belong to CPMS, whose people never log into the POS.
///
/// **Accepting here is not CPMS approval.** It says the store will serve the request; it
/// reserves no stock, books no money, and never mints or changes the CPMS token.
class RequisitionService {
  RequisitionService({ApiClient? client})
    : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  static const String requisitionsPath = '/api/v1/requisitions/';
  static const String verifyPath = '/api/v1/tokens/verify/';
  static const String releasePath = '/api/v1/tokens/release/';

  /// The server's page size; the bound below is expressed in those units.
  static const int _maxPages = 40;

  /// What a REVIEW write says when its 200 arrived but could not be read.
  ///
  /// The decision is stored before its answer comes back, so this body is a state to reload
  /// rather than a failure to repeat.
  static const String unreadableDecisionCopy =
      'The decision may or may not have been saved. Showing the request as the '
      'server holds it.';

  /// Every requisition, optionally narrowed to one status, following pagination.
  ///
  /// The queue reads `status=WAITING` oldest-first and needs ALL of it, so the walk lives in
  /// [ApiClient.getAll] (one place follows the envelope) rather than in a second `while
  /// (next)` loop here. The status travels with EVERY page: a filter sent only on page 1
  /// would page the unfiltered list.
  ///
  /// Bounded: 40 pages x DRF's 50 rows. Hitting the bound fails loudly instead of returning a
  /// silently truncated queue a manager would read as complete.
  Future<List<Requisition>> fetchRequisitions({String? status}) async {
    try {
      return await _client.getAll<Requisition>(
        requisitionsPath,
        Requisition.fromJson,
        queryParameters: {'status': ?status},
        maxPages: _maxPages,
      );
    } on DioException catch (error) {
      throw RequisitionServiceException(
        _messageFor(error),
        code: _serverCode(error),
      );
    } on FormatException {
      throw const RequisitionServiceException(
        'The requisition list did not finish loading. Try again.',
      );
    }
  }

  /// One request, as the server holds it right now.
  ///
  /// This is the read a screen does after a stale decision (409) or an uncertain write: the
  /// answer may already exist, and only the server knows what it is.
  Future<Requisition> fetchRequisition(int id) async {
    final Map<String, dynamic> data;
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '$requisitionsPath$id/',
      );
      final body = response.data;
      if (body == null) {
        throw const RequisitionServiceException(
          'The server returned an empty response.',
        );
      }
      data = body;
    } on DioException catch (error) {
      throw RequisitionServiceException(
        _messageFor(error),
        code: _serverCode(error),
      );
    }
    return _decode(Requisition.fromJson, data);
  }

  /// How many requests are waiting for the store, from the server's own `count`.
  ///
  /// Page 1 only: `Paged.total` is the size of the whole collection, so the sidebar marker
  /// never walks pages to count them. A failed read throws instead of answering 0 — a failed
  /// count is not a confirmed zero.
  Future<int> waitingCount() async {
    try {
      final page = await _client.getList<Requisition>(
        requisitionsPath,
        Requisition.fromJson,
        queryParameters: {
          'status': RequisitionStatus.waiting.apiValue,
          'page': 1,
        },
      );
      return page.total;
    } on DioException catch (error) {
      throw RequisitionServiceException(
        _messageFor(error),
        code: _serverCode(error),
      );
    } on FormatException {
      throw const RequisitionServiceException(
        'The waiting count could not be read. Try again.',
      );
    }
  }

  /// Answers the request line by line (decision 10) and returns its updated state.
  ///
  /// Every stored line needs an explicit answer and at least one must be available; the
  /// server enforces that and refuses an all-false Accept with a 400 directing staff to
  /// whole Decline. Nothing here edits a quantity or a price.
  Future<Requisition> accept(
    int id,
    List<RequisitionLineDecision> decisions,
  ) async {
    final body = await _post(
      '$requisitionsPath$id/accept/',
      body: {
        'items': [for (final decision in decisions) decision.toJson()],
      },
      writeOutcomeUnknown: true,
    );
    return _decodeWrite(body);
  }

  /// Declines the WHOLE request (decision 09). A reason is required; the server refuses a
  /// blank one.
  Future<Requisition> decline(int id, String reason) async {
    final body = await _post(
      '$requisitionsPath$id/decline/',
      body: {'decline_reason': reason},
      writeOutcomeUnknown: true,
    );
    return _decodeWrite(body);
  }

  /// Verifies a token and returns what it is for. Moves NOTHING.
  Future<TokenVerification> verifyToken(String token) async {
    final body = await _post(verifyPath, body: {'token': token});
    return _decode(TokenVerification.fromJson, body);
  }

  /// Releases the materials a token authorises.
  ///
  /// This is the only irreversible action in Phase 5: it FIFO-deducts stock, creates a sale and
  /// posts a receivable. The server re-checks the token under `select_for_update`, so a token
  /// used twice is refused rather than double-released.
  Future<ReleaseResult> release(String token) async {
    final body = await _post(releasePath, body: {'token': token});
    return _decode(ReleaseResult.fromJson, body);
  }

  /// POSTs [body] and returns the decoded object.
  ///
  /// A server message wins whenever there is one, because the requisition guards explain
  /// themselves better than any generic wording could.
  ///
  /// [writeOutcomeUnknown] marks a REVIEW decision. The row it stored exists before its answer
  /// arrives, so a 2xx this build cannot read (an empty body, a drifted shape) leaves the
  /// outcome UNKNOWN: the screen must reload before it offers Accept or Decline again. A 4xx is
  /// still an ANSWER — the server refused and wrote nothing.
  Future<Map<String, dynamic>> _post(
    String path, {
    Map<String, dynamic> body = const {},
    bool writeOutcomeUnknown = false,
  }) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        path,
        data: body,
      );
      final data = response.data;
      if (data == null) {
        throw RequisitionServiceException(
          writeOutcomeUnknown
              ? unreadableDecisionCopy
              : 'The server returned an empty response.',
          outcomeUnknown: writeOutcomeUnknown,
        );
      }
      return data;
    } on DioException catch (error) {
      // The CODE travels with the message (Phase 3 Task 4): `NO_OPEN_SHIFT` is
      // the one release refusal the screen can FIX, and only the code says so.
      //
      // No response at all means a WRITE may have landed unseen (timeout, dropped
      // connection), so [RequisitionServiceException.outcomeUnknown] tells the screen to
      // reload before offering the same decision again.
      throw RequisitionServiceException(
        _messageFor(error),
        code: _serverCode(error),
        outcomeUnknown:
            error.response == null ||
            (writeOutcomeUnknown && _isSuccess(error.response?.statusCode)),
      );
    } on FormatException {
      throw RequisitionServiceException(
        writeOutcomeUnknown
            ? unreadableDecisionCopy
            : 'The requisition data could not be read. Try again.',
        outcomeUnknown: writeOutcomeUnknown,
      );
    } catch (_) {
      if (!writeOutcomeUnknown) rethrow;
      throw const RequisitionServiceException(
        unreadableDecisionCopy,
        outcomeUnknown: true,
      );
    }
  }

  /// Reads the row a stored decision answered with.
  ///
  /// Anything this build cannot read — a missing field, a JSON TYPE drift such as `items` sent
  /// as a string — leaves the outcome UNKNOWN rather than refused: the decision is already in
  /// the server, so the screen reloads before offering Accept or Decline again.
  Requisition _decodeWrite(Map<String, dynamic> body) {
    try {
      return Requisition.fromJson(body);
    } catch (_) {
      throw const RequisitionServiceException(
        unreadableDecisionCopy,
        outcomeUnknown: true,
      );
    }
  }

  /// Whether an HTTP answer means the server ACCEPTED the request it was given.
  bool _isSuccess(int? status) =>
      status != null && status >= 200 && status < 300;

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
    if (_conflictCopy[code] case final copy?) return copy;
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
  /// next step is asking the project for a new one. Phase 1b adds the two store-review
  /// words: WAITING means a store manager has not answered yet, and DECLINED means the
  /// store refused it (decisions 09 and 13). Both are checked before the generic "token
  /// already used" refusal server-side, so a spent Decline token still explains itself.
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
    'REQUISITION_WAITING':
        'The store has not accepted this request yet. A store manager must accept it '
        'under Project requests first.',
    'REQUISITION_DECLINED':
        'The store declined this request, so nothing can be released for it.',
  };

  /// The one refusal a REVIEW screen can meet: somebody already answered this request.
  ///
  /// Two managers on two screens, or a decision that raced a CPMS close. It is not a
  /// failure to retry — the answer exists — so the words send staff to the current state
  /// instead of offering the same decision again.
  static const Map<String, String> _conflictCopy = {
    'REQUEST_ALREADY_REVIEWED':
        'This request was already answered. Showing its current state.',
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
