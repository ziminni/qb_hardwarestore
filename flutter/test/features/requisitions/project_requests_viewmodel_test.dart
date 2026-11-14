// Phase 1b Task 7 (decisions 09, 10 and 13): the "Requests from projects" queue's
// screen-scoped viewmodel. What it owns is the part a widget test is bad at:
//   * the sidebar's waiting count is its own read and never a guess (a failed
//     read is NOT a confirmed zero),
//   * a decision that lands is shown from the SERVER's answer, then refreshed,
//   * a saved decision whose refresh failed says so instead of inviting a
//     second answer,
//   * a write with an unknown outcome (timeout) or a stale one (409) reloads
//     the authoritative detail before offering the buttons again, and stays
//     blocked with an explicit retry when that reload fails,
//   * one request at a time: a double tap writes once.
import 'dart:async';
import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:client/features/requisitions/viewmodels/project_requests_viewmodel.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

Requisition _request({
  int id = 7,
  String reqNumber = 'REQ-20261107-0007',
  String status = 'WAITING',
  String project = '2-Storey House - Mandaue',
  String customer = 'Dela Cruz Construction',
  String requestedBy = 'Forman Reyes',
  String? approver = 'Engr. Reyes',
  String notes = 'Deliver to gate 2.',
  String declineReason = '',
  double? expectedAmount,
  List<RequisitionItem>? items,
}) => Requisition(
  id: id,
  reqNumber: reqNumber,
  rawStatus: status,
  projectName: project,
  projectCustomerName: customer,
  requestedByName: requestedBy,
  items:
      items ??
      const [
        RequisitionItem(
          id: 21,
          variantId: 4,
          variantName: '40 kg',
          quantity: 4,
          releasedQty: 0,
          productName: 'Portland Cement',
          unit: '40 kg bag',
        ),
      ],
  cpmsRequestId: 'CPMS-REQ-8842',
  createdAt: DateTime(2026, 11, 7, 8, 15),
  approverName: approver,
  notes: notes,
  declineReason: declineReason,
  expectedAmount: expectedAmount,
);

/// One list read, when a test needs to answer calls OUT OF ORDER.
class _ListReply {
  _ListReply({this.rows = const [], this.error, this.gate});

  final List<Requisition> rows;
  final String? error;

  /// Held open, this read resolves late — that is how two loads overlap.
  final Completer<void>? gate;
}

/// A repository that answers with what the test wrote down and counts the calls.
class _StubRepository extends RequisitionRepository {
  _StubRepository() : super();

  List<Requisition> rows = const [];
  int waiting = 0;
  String? listError;
  String? countError;
  Requisition? detail;
  String? detailError;
  Requisition? writeResult;
  RequisitionServiceException? writeError;
  Completer<void>? gate;

  int listCalls = 0;
  int countCalls = 0;
  int detailCalls = 0;
  int acceptCalls = 0;
  int declineCalls = 0;
  final List<String?> requestedStatuses = [];
  List<RequisitionLineDecision>? lastDecisions;
  String? lastReason;

  /// Answers for one list read, by 0-based call number, overriding the fields above.
  final Map<int, _ListReply> listReplies = {};

  /// The count one count read answers, by 0-based call number.
  final Map<int, int> countByCall = {};
  final Map<int, Completer<void>> countGates = {};

  @override
  Future<List<Requisition>> fetchRequisitions({String? status}) async {
    final call = listCalls++;
    requestedStatuses.add(status);
    final reply = listReplies[call];
    if (reply != null) {
      final replyGate = reply.gate;
      if (replyGate != null) await replyGate.future;
      final replyError = reply.error;
      if (replyError != null) throw RequisitionServiceException(replyError);
      return reply.rows;
    }
    final failure = listError;
    if (failure != null) throw RequisitionServiceException(failure);
    if (status == null) return rows;
    return rows.where((row) => row.rawStatus == status).toList();
  }

  @override
  Future<int> waitingCount() async {
    final call = countCalls++;
    final gate = countGates[call];
    if (gate != null) await gate.future;
    final failure = countError;
    if (failure != null) throw RequisitionServiceException(failure);
    return countByCall[call] ?? waiting;
  }

  @override
  Future<Requisition> fetchRequisition(int id) async {
    detailCalls++;
    final failure = detailError;
    if (failure != null) throw RequisitionServiceException(failure);
    return detail ?? rows.firstWhere((row) => row.id == id);
  }

  @override
  Future<Requisition> accept(
    int id,
    List<RequisitionLineDecision> decisions,
  ) async {
    acceptCalls++;
    lastDecisions = decisions;
    final gate = this.gate;
    if (gate != null) await gate.future;
    final failure = writeError;
    if (failure != null) throw failure;
    return writeResult ?? _request(id: id, status: 'ACCEPTED');
  }

  @override
  Future<Requisition> decline(int id, String reason) async {
    declineCalls++;
    lastReason = reason;
    final failure = writeError;
    if (failure != null) throw failure;
    return writeResult ??
        _request(id: id, status: 'DECLINED', declineReason: reason);
  }
}

/// A fake transport, so the queue can be driven through the REAL service below.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);
  final ResponseBody Function(RequestOptions options) respond;
  HttpClientAdapter? replaced;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? s,
    Future<void>? c,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// One requisition exactly as `GET /api/v1/requisitions/` sends it.
Map<String, dynamic> _requisitionJson({
  int id = 7,
  String status = 'WAITING',
}) => {
  'id': id,
  'req_number': 'REQ-20261107-0007',
  'status': status,
  'project_name': '2-Storey House - Mandaue',
  'project_customer_name': 'Dela Cruz Construction',
  'requested_by_name': 'Forman Reyes',
  'items': [
    {
      'id': 21,
      'variant': 4,
      'variant_name': '40 kg',
      'quantity': '4.00',
      'released_qty': '0.00',
    },
  ],
  'created_at': '2026-11-07T08:15:00Z',
  'approver_name': 'Engr. Reyes',
  'notes': 'Deliver to gate 2.',
};

ProjectRequestsViewmodel _viewmodel(_StubRepository repository) =>
    ProjectRequestsViewmodel(repository: repository);

void main() {
  group('loading the queue', () {
    test('the default filter is Waiting for store', () async {
      final repository = _StubRepository()
        ..rows = [_request(), _request(id: 8, status: 'ACCEPTED')]
        ..waiting = 1;
      final viewmodel = _viewmodel(repository);

      await viewmodel.load();

      expect(viewmodel.status, RequisitionStatus.waiting);
      expect(repository.requestedStatuses.single, 'WAITING');
      expect(viewmodel.requests.map((row) => row.id), [7]);
      expect(viewmodel.loadError, isNull);
    });

    test(
      'the badge count is a separate read and ignores the status filter',
      () async {
        final repository = _StubRepository()
          ..rows = [_request()]
          ..waiting = 9;
        final viewmodel = _viewmodel(repository);

        await viewmodel.load();
        await viewmodel.selectStatus(RequisitionStatus.accepted);

        expect(repository.requestedStatuses, ['WAITING', 'ACCEPTED']);
        expect(viewmodel.status, RequisitionStatus.accepted);
        expect(
          viewmodel.waitingCount,
          9,
          reason:
              'the sidebar count is ALL waiting rows, not the filtered list',
        );
      },
    );

    test('a zero from the server is a real count, not a missing one', () async {
      final repository = _StubRepository()..waiting = 0;
      final viewmodel = _viewmodel(repository);

      await viewmodel.load();

      expect(viewmodel.waitingCount, 0);
    });

    test('a failed count read leaves the badge unknown, never zero', () async {
      final repository = _StubRepository()
        ..rows = [_request()]
        ..countError = 'offline';
      final viewmodel = _viewmodel(repository);

      await viewmodel.load();

      expect(viewmodel.waitingCount, isNull);
      expect(
        viewmodel.requests,
        hasLength(1),
        reason: 'a failed badge read must not fail the list',
      );
    });

    test('a failed first load reports once and keeps no rows', () async {
      final repository = _StubRepository()..listError = 'Server down.';
      final viewmodel = _viewmodel(repository);

      await viewmodel.load();

      expect(viewmodel.loadError, 'Server down.');
      expect(viewmodel.requests, isEmpty);
    });

    test('a reload failure keeps the rows it already had', () async {
      final repository = _StubRepository()..rows = [_request()];
      final viewmodel = _viewmodel(repository);
      await viewmodel.load();

      repository.listError = 'Server down.';
      await viewmodel.load();

      expect(viewmodel.loadError, 'Server down.');
      expect(viewmodel.requests.map((row) => row.id), [7]);
    });
  });

  group('a decision that lands', () {
    test(
      'accept shows the server row, then refreshes list and count',
      () async {
        final repository = _StubRepository()
          ..rows = [_request()]
          ..waiting = 1
          ..writeResult = _request(status: 'ACCEPTED');
        final viewmodel = _viewmodel(repository);
        await viewmodel.load();
        repository.rows = [_request(status: 'ACCEPTED')];
        repository.waiting = 0;

        final result = await viewmodel.accept(7, const [
          RequisitionLineDecision(lineId: 21, available: true),
        ]);

        expect(result.outcome, ReviewOutcome.saved);
        expect(result.message, isNull);
        expect(repository.lastDecisions, hasLength(1));
        expect(repository.lastDecisions!.single.lineId, 21);
        expect(
          repository.listCalls,
          2,
          reason: 'the queue is reloaded after the decision',
        );
        expect(
          repository.countCalls,
          2,
          reason: 'the badge is refreshed after the decision',
        );
        expect(viewmodel.waitingCount, 0);
        expect(
          viewmodel.detailFor(7)!.status,
          RequisitionStatus.accepted,
          reason: 'the returned row is the state the dialog shows',
        );
      },
    );

    test('a saved decision whose refresh failed says it was saved', () async {
      final repository = _StubRepository()
        ..rows = [_request()]
        ..waiting = 1;
      final viewmodel = _viewmodel(repository);
      await viewmodel.load();

      repository.listError = 'Server down.';
      final result = await viewmodel.accept(7, const [
        RequisitionLineDecision(lineId: 21, available: true),
      ]);

      expect(result.outcome, ReviewOutcome.saved);
      expect(
        result.message,
        contains('saved'),
        reason: 'a failed refresh must not read as a failed decision',
      );
      expect(
        viewmodel.loadError,
        isNull,
        reason: 'the banner is not a second way of saying the same thing',
      );
      expect(
        viewmodel.detailFor(7)!.status,
        RequisitionStatus.accepted,
        reason: 'the returned row survives the failed refresh',
      );
    });

    test('a double tap writes once', () async {
      final repository = _StubRepository()
        ..rows = [_request()]
        ..gate = Completer<void>();
      final viewmodel = _viewmodel(repository);
      await viewmodel.load();

      final first = viewmodel.accept(7, const [
        RequisitionLineDecision(lineId: 21, available: true),
      ]);
      expect(viewmodel.isSubmitting(7), isTrue);
      final second = await viewmodel.accept(7, const [
        RequisitionLineDecision(lineId: 21, available: true),
      ]);
      expect(second.outcome, ReviewOutcome.refused);
      expect(viewmodel.isSubmitting(7), isTrue, reason: 'still in flight');

      repository.gate!.complete();
      expect((await first).outcome, ReviewOutcome.saved);
      expect(repository.acceptCalls, 1);
      expect(viewmodel.isSubmitting(7), isFalse);
    });

    test('decline sends the whole-request reason', () async {
      final repository = _StubRepository()..rows = [_request()];
      final viewmodel = _viewmodel(repository);
      await viewmodel.load();

      final result = await viewmodel.decline(7, 'Cannot supply this request');

      expect(result.outcome, ReviewOutcome.saved);
      expect(repository.lastReason, 'Cannot supply this request');
    });
  });

  group('an uncertain or stale write reloads before re-enabling', () {
    test('a timeout reloads the detail and offers the buttons again', () async {
      final repository = _StubRepository()
        ..rows = [_request()]
        ..writeError = const RequisitionServiceException(
          'Cannot connect to the BuildPro server.',
          outcomeUnknown: true,
        )
        ..detail = _request();
      final viewmodel = _viewmodel(repository);
      await viewmodel.load();

      final result = await viewmodel.accept(7, const [
        RequisitionLineDecision(lineId: 21, available: true),
      ]);

      expect(repository.detailCalls, 1);
      expect(result.outcome, ReviewOutcome.refused);
      expect(viewmodel.isBlocked(7), isFalse);
      expect(viewmodel.isSubmitting(7), isFalse);
    });

    test(
      'a timeout that cannot be reloaded stays blocked with a retry',
      () async {
        final repository = _StubRepository()
          ..rows = [_request()]
          ..writeError = const RequisitionServiceException(
            'Cannot connect to the BuildPro server.',
            outcomeUnknown: true,
          )
          ..detailError = 'Server down.';
        final viewmodel = _viewmodel(repository);
        await viewmodel.load();

        final result = await viewmodel.accept(7, const [
          RequisitionLineDecision(lineId: 21, available: true),
        ]);

        expect(result.outcome, ReviewOutcome.blocked);
        expect(viewmodel.isBlocked(7), isTrue);
        expect(
          result.message,
          contains('Retry refresh'),
          reason: 'the reviewer is told how to get out of the blocked state',
        );

        final again = await viewmodel.accept(7, const [
          RequisitionLineDecision(lineId: 21, available: true),
        ]);
        expect(again.outcome, ReviewOutcome.refused);
        expect(
          repository.acceptCalls,
          1,
          reason: 'no second write while blocked',
        );
      },
    );

    test('Retry refresh clears the block once the detail loads', () async {
      final repository = _StubRepository()
        ..rows = [_request()]
        ..writeError = const RequisitionServiceException(
          'Cannot connect to the BuildPro server.',
          outcomeUnknown: true,
        )
        ..detailError = 'Server down.';
      final viewmodel = _viewmodel(repository);
      await viewmodel.load();
      await viewmodel.accept(7, const [
        RequisitionLineDecision(lineId: 21, available: true),
      ]);

      repository
        ..detailError = null
        ..detail = _request(status: 'ACCEPTED');
      final retried = await viewmodel.retryRefresh(7);

      expect(retried, isTrue);
      expect(viewmodel.isBlocked(7), isFalse);
      expect(viewmodel.detailFor(7)!.status, RequisitionStatus.accepted);
    });

    test('Retry refresh that fails again keeps the request blocked', () async {
      final repository = _StubRepository()
        ..rows = [_request()]
        ..writeError = const RequisitionServiceException(
          'Cannot connect to the BuildPro server.',
          outcomeUnknown: true,
        )
        ..detailError = 'Server down.';
      final viewmodel = _viewmodel(repository);
      await viewmodel.load();
      await viewmodel.accept(7, const [
        RequisitionLineDecision(lineId: 21, available: true),
      ]);

      expect(await viewmodel.retryRefresh(7), isFalse);
      expect(viewmodel.isBlocked(7), isTrue);
    });

    test(
      'a 409 reloads the current state instead of offering the write again',
      () async {
        final repository = _StubRepository()
          ..rows = [_request()]
          ..writeError = const RequisitionServiceException(
            'This request was already answered. Showing its current state.',
            code: 'REQUEST_ALREADY_REVIEWED',
          )
          ..detail = _request(
            status: 'DECLINED',
            declineReason: 'Out of stock',
          );
        final viewmodel = _viewmodel(repository);
        await viewmodel.load();

        final result = await viewmodel.accept(7, const [
          RequisitionLineDecision(lineId: 21, available: true),
        ]);

        expect(repository.detailCalls, 1);
        expect(result.outcome, ReviewOutcome.refused);
        expect(result.message, contains('already answered'));
        expect(viewmodel.detailFor(7)!.status, RequisitionStatus.declined);
        expect(viewmodel.isBlocked(7), isFalse);
      },
    );

    test('a plain refusal writes nothing more and reloads nothing', () async {
      final repository = _StubRepository()
        ..rows = [_request()]
        ..writeError = const RequisitionServiceException(
          'Give a reason for each line the store will not serve.',
          code: 'INVALID_REQUEST_REVIEW',
        );
      final viewmodel = _viewmodel(repository);
      await viewmodel.load();

      final result = await viewmodel.accept(7, const [
        RequisitionLineDecision(lineId: 21, available: false),
      ]);

      expect(result.outcome, ReviewOutcome.refused);
      expect(repository.detailCalls, 0);
      expect(viewmodel.reviewMessage(7), contains('reason'));
      expect(viewmodel.isBlocked(7), isFalse);
    });

    test('one request being saved does not block another', () async {
      final repository = _StubRepository()
        ..rows = [_request(), _request(id: 8)]
        ..gate = Completer<void>();
      final viewmodel = _viewmodel(repository);
      await viewmodel.load();

      final first = viewmodel.accept(7, const [
        RequisitionLineDecision(lineId: 21, available: true),
      ]);
      expect(viewmodel.isSubmitting(7), isTrue);
      expect(viewmodel.isSubmitting(8), isFalse);

      repository.gate!.complete();
      await first;
    });
  });

  // Phase 1b Task 7 review round 1. Driven through the REAL service over a fake transport:
  // the defect was that a 200 nobody could read reached the viewmodel as a DEFINITE refusal,
  // so a stub handing it a ready-made exception would prove nothing.
  group('an unreadable 200 does not read as a refusal', () {
    late ApiClient client;
    late _FakeAdapter adapter;
    late ResponseBody Function(RequestOptions) responder;
    late List<String> calls;

    setUpAll(() {
      client = ApiClient.instance..init();
      adapter = _FakeAdapter((options) {
        calls.add('${options.method} ${options.path}');
        return responder(options);
      });
      adapter.replaced = client.dio.httpClientAdapter;
      client.dio.httpClientAdapter = adapter;
    });

    tearDownAll(() {
      final replaced = adapter.replaced;
      if (replaced != null) client.dio.httpClientAdapter = replaced;
    });

    setUp(() => calls = []);

    ProjectRequestsViewmodel httpViewmodel() => ProjectRequestsViewmodel(
      repository: RequisitionRepository(
        service: RequisitionService(client: client),
      ),
    );

    ResponseBody queue(String status) => _json({
      'count': 1,
      'next': null,
      'previous': null,
      'results': [_requisitionJson(id: 7, status: status)],
    });

    int writesSeen() => calls.where((call) => call.contains('/accept/')).length;

    test(
      'a malformed accept answer refreshes the detail before the buttons return',
      () async {
        responder = (options) {
          final path = options.path;
          if (path.contains('/accept/')) return _json({'id': 7});
          if (path.contains('/requisitions/7/')) {
            return _json(_requisitionJson(status: 'ACCEPTED'));
          }
          return queue('ACCEPTED');
        };
        final viewmodel = httpViewmodel();
        await viewmodel.load();
        calls.clear();

        final result = await viewmodel.accept(7, const [
          RequisitionLineDecision(lineId: 21, available: true),
        ]);

        expect(result.outcome, isNot(ReviewOutcome.saved));
        expect(
          calls,
          contains('GET /api/v1/requisitions/7/'),
          reason:
              'the decision may be stored, so its current state is read before '
              'Accept or Decline come back',
        );
        expect(viewmodel.detailFor(7)!.status, RequisitionStatus.accepted);
        expect(viewmodel.isBlocked(7), isFalse);
        expect(viewmodel.isSubmitting(7), isFalse);
      },
    );

    test('an empty decline answer is unknown too', () async {
      responder = (options) {
        final path = options.path;
        if (path.contains('/decline/')) {
          return ResponseBody.fromString(
            '',
            200,
            headers: {
              Headers.contentTypeHeader: [Headers.jsonContentType],
            },
          );
        }
        if (path.contains('/requisitions/7/')) {
          return _json(_requisitionJson(status: 'DECLINED'));
        }
        return queue('DECLINED');
      };
      final viewmodel = httpViewmodel();
      await viewmodel.load();
      calls.clear();

      final result = await viewmodel.decline(7, 'Cannot supply this request');

      expect(result.outcome, isNot(ReviewOutcome.saved));
      expect(calls, contains('GET /api/v1/requisitions/7/'));
      expect(viewmodel.detailFor(7)!.status, RequisitionStatus.declined);
      expect(viewmodel.isBlocked(7), isFalse);
    });

    test(
      'a malformed answer whose detail read fails stays blocked with a retry',
      () async {
        var detailFails = true;
        responder = (options) {
          final path = options.path;
          if (path.contains('/accept/')) return _json({'id': 7});
          if (path.contains('/requisitions/7/')) {
            return detailFails
                ? _json({'detail': 'Server error.'}, status: 500)
                : _json(_requisitionJson(status: 'ACCEPTED'));
          }
          return queue('WAITING');
        };
        final viewmodel = httpViewmodel();
        await viewmodel.load();

        final result = await viewmodel.accept(7, const [
          RequisitionLineDecision(lineId: 21, available: true),
        ]);

        expect(result.outcome, ReviewOutcome.blocked);
        expect(viewmodel.isBlocked(7), isTrue);
        expect(result.message, contains('Retry refresh'));

        final writes = writesSeen();
        final again = await viewmodel.accept(7, const [
          RequisitionLineDecision(lineId: 21, available: true),
        ]);
        expect(again.outcome, ReviewOutcome.refused);
        expect(
          writesSeen(),
          writes,
          reason: 'a blocked request cannot be answered a second time',
        );

        detailFails = false;
        expect(await viewmodel.retryRefresh(7), isTrue);
        expect(viewmodel.isBlocked(7), isFalse);
        expect(viewmodel.detailFor(7)!.status, RequisitionStatus.accepted);
      },
    );
  });

  group('an out-of-order list read cannot replace a newer selection', () {
    test(
      'an older SUCCESS finishing last leaves the newer rows alone',
      () async {
        final gate = Completer<void>();
        final repository = _StubRepository()
          ..listReplies[0] = _ListReply(rows: [_request()], gate: gate)
          ..listReplies[1] = _ListReply(
            rows: [_request(id: 8, status: 'ACCEPTED')],
          );
        final viewmodel = _viewmodel(repository);

        final older = viewmodel.load();
        await viewmodel.selectStatus(RequisitionStatus.accepted);
        expect(viewmodel.requests.map((row) => row.id), [8]);

        gate.complete();
        await older;

        expect(viewmodel.status, RequisitionStatus.accepted);
        expect(
          viewmodel.requests.map((row) => row.id),
          [8],
          reason:
              'the read started for the OLD chip must not describe the new one',
        );
        expect(viewmodel.loadError, isNull);
      },
    );

    test(
      'an older ERROR finishing last does not fail the newer rows',
      () async {
        final gate = Completer<void>();
        final repository = _StubRepository()
          ..listReplies[0] = _ListReply(error: 'Server down.', gate: gate)
          ..listReplies[1] = _ListReply(
            rows: [_request(id: 8, status: 'ACCEPTED')],
          );
        final viewmodel = _viewmodel(repository);

        final older = viewmodel.load();
        await viewmodel.selectStatus(RequisitionStatus.accepted);

        gate.complete();
        await older;

        expect(
          viewmodel.loadError,
          isNull,
          reason: 'the newer chip loaded fine, so its screen has no error',
        );
        expect(viewmodel.requests.map((row) => row.id), [8]);
      },
    );

    test(
      'an older COUNT finishing last does not overwrite the badge',
      () async {
        final countGate = Completer<void>();
        final repository = _StubRepository()
          ..countGates[0] = countGate
          ..countByCall[0] = 3
          ..countByCall[1] = 0;
        final viewmodel = _viewmodel(repository);

        final older = viewmodel.load();
        // The older read is inside ITS count read now, so the gate below is the
        // one it is waiting on.
        await Future<void>.delayed(Duration.zero);
        await viewmodel.selectStatus(RequisitionStatus.accepted);
        expect(viewmodel.waitingCount, 0);

        countGate.complete();
        await older;

        expect(
          viewmodel.waitingCount,
          0,
          reason: 'the badge shows the newest count the server confirmed',
        );
      },
    );

    test('a stale list cannot undo a decision that was saved', () async {
      final gate = Completer<void>();
      final repository = _StubRepository()
        ..listReplies[0] = _ListReply(rows: [_request()], gate: gate)
        ..listReplies[1] = _ListReply(rows: [_request(status: 'ACCEPTED')]);
      final viewmodel = _viewmodel(repository);

      final older = viewmodel.load();
      final result = await viewmodel.accept(7, const [
        RequisitionLineDecision(lineId: 21, available: true),
      ]);
      expect(result.outcome, ReviewOutcome.saved);
      expect(viewmodel.detailFor(7)!.status, RequisitionStatus.accepted);

      gate.complete();
      await older;

      expect(
        viewmodel.isLoading,
        isFalse,
        reason:
            'the newer review refresh owns the spinner now, so it must come '
            'down even though the older read is the one that raised it',
      );
      expect(
        viewmodel.detailFor(7)!.status,
        RequisitionStatus.accepted,
        reason:
            'a list read that started BEFORE the decision cannot put the '
            'request back to WAITING and invite a second answer',
      );
      expect(viewmodel.requests.single.status, RequisitionStatus.accepted);
    });
  });

  group('the screen going away mid-read', () {
    test('a load that resolves after dispose does not notify', () async {
      final gate = Completer<void>();
      final repository = _StubRepository()
        ..listReplies[0] = _ListReply(rows: [_request()], gate: gate);
      final viewmodel = _viewmodel(repository);

      final pending = viewmodel.load();
      viewmodel.dispose();
      gate.complete();

      await pending;
    });

    test('a decision that resolves after dispose does not notify', () async {
      final repository = _StubRepository()
        ..rows = [_request()]
        ..gate = Completer<void>();
      final viewmodel = _viewmodel(repository);
      await viewmodel.load();

      final pending = viewmodel.accept(7, const [
        RequisitionLineDecision(lineId: 21, available: true),
      ]);
      viewmodel.dispose();
      repository.gate!.complete();

      await pending;
    });
  });

  // Review round 2: the tail of a list read used to clear the spinner with no
  // generation check, so an OLD count resolving while a NEWER list was still in
  // flight switched the spinner off early — and when the newer list then
  // resolved, it saw "already false" and never notified, leaving changed rows or
  // a new error on screen unpainted.
  group('a late count from an older read cannot clear the newer spinner', () {
    test('an older count cannot turn off the newer loading state', () async {
      final oldCount = Completer<void>();
      final newList = Completer<void>();
      final repository = _StubRepository()
        ..listReplies[0] = _ListReply(rows: [_request()])
        ..listReplies[1] = _ListReply(
          rows: [_request(id: 8, status: 'ACCEPTED')],
          gate: newList,
        )
        ..countGates[0] = oldCount
        ..countByCall[0] = 3
        ..countByCall[1] = 0;
      final viewmodel = _viewmodel(repository);
      var notifications = 0;
      viewmodel.addListener(() => notifications++);

      final older = viewmodel.load();
      // The older read is inside ITS count read now.
      await Future<void>.delayed(Duration.zero);
      final newer = viewmodel.selectStatus(RequisitionStatus.accepted);
      final beforeOld = notifications;

      oldCount.complete();
      await older;

      expect(
        viewmodel.isLoading,
        isTrue,
        reason: 'the newer list read is still in flight',
      );
      expect(
        notifications,
        beforeOld,
        reason: 'the older read has nothing new to paint',
      );

      newList.complete();
      await newer;

      expect(viewmodel.isLoading, isFalse);
      expect(viewmodel.requests.map((row) => row.id), [8]);
      expect(
        notifications,
        greaterThan(beforeOld),
        reason: 'the newer read repaints the rows it just loaded',
      );
    });

    test(
      'a newer list FAILURE still ends loading and notifies its error',
      () async {
        final oldCount = Completer<void>();
        final newList = Completer<void>();
        final repository = _StubRepository()
          ..listReplies[0] = _ListReply(rows: [_request()])
          ..listReplies[1] = _ListReply(error: 'Server down.', gate: newList)
          ..countGates[0] = oldCount;
        final viewmodel = _viewmodel(repository);
        var notifications = 0;
        viewmodel.addListener(() => notifications++);

        final older = viewmodel.load();
        await Future<void>.delayed(Duration.zero);
        final newer = viewmodel.selectStatus(RequisitionStatus.accepted);

        oldCount.complete();
        await older;
        final afterOld = notifications;

        newList.complete();
        await newer;

        expect(viewmodel.isLoading, isFalse);
        expect(viewmodel.loadError, 'Server down.');
        expect(
          notifications,
          greaterThan(afterOld),
          reason: 'the new error must reach the screen, not change silently',
        );
      },
    );
  });
}
