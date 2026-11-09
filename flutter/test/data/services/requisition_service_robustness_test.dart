// Phase 5 review findings 1 and 2 (2026-10-17): what the service does when the wire is not what it
// expects. Kept in its own file rather than appended to requisition_service_test.dart, because the
// existing suite's shape is the happy path and these are the two ways it goes wrong.
import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  late ApiClient client;
  late _FakeAdapter adapter;
  late ResponseBody Function(RequestOptions) responder;

  RequisitionService service() => RequisitionService(client: client);

  setUpAll(() {
    // init() is NOT idempotent (dio is `late final`), so it happens once and only the adapter moves.
    client = ApiClient.instance..init();
    adapter = _FakeAdapter((options) => responder(options));
    adapter.replaced = client.dio.httpClientAdapter;
    client.dio.httpClientAdapter = adapter;
  });

  tearDownAll(() {
    if (adapter.replaced != null) {
      client.dio.httpClientAdapter = adapter.replaced!;
    }
  });

  test(
    'a DRIFTED success body reports a service error, not a raw parse crash',
    () async {
      // The server answered 200 but its shape moved: verify's parser needs keys that are absent.
      // Before the fix this threw a bare FormatException, which the viewmodel never catches - so
      // verify silently did nothing and release left its spinner running forever.
      responder = (options) => _json({'token': 'a-token'});
      await expectLater(
        service().verifyToken('a-token'),
        throwsA(
          isA<RequisitionServiceException>().having(
            (e) => e.outcomeUnknown,
            'outcomeUnknown',
            isFalse,
          ),
        ),
      );
    },
  );

  test('a MALFORMED token does not blame the requisition list', () async {
    // DRF rejects a non-UUID with {'token': [...]}, which carries no `detail`, so the old
    // _serverDetail returned null and a clerk who mistyped was told the REQUISITIONS failed to load.
    responder = (options) => _json({
      'token': ['Enter a valid UUID.'],
    }, status: 400);
    await expectLater(
      service().verifyToken('not-a-uuid'),
      throwsA(
        isA<RequisitionServiceException>().having(
          (e) => e.message,
          'message',
          isNot('The requisitions could not be loaded.'),
        ),
      ),
    );
  });

  // Phase 1b (decisions 09/10): Accept and Decline are WRITES. A write that left this
  // machine and never got an answer may or may not have been stored, so the screen has to
  // reload before it lets anyone answer again. A 400/409 is an ANSWER: nothing unknown.
  group('an uncertain write is flagged so the screen reloads first', () {
    test(
      'a timeout carries no HTTP answer, so the outcome is unknown',
      () async {
        responder = (options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        );

        await expectLater(
          service().accept(7, const [
            RequisitionLineDecision(lineId: 21, available: true),
          ]),
          throwsA(
            isA<RequisitionServiceException>()
                .having((e) => e.outcomeUnknown, 'outcomeUnknown', isTrue)
                .having(
                  (e) => e.message,
                  'message',
                  'The requisitions could not be loaded.',
                ),
          ),
        );
      },
    );

    test('a dropped connection during a decline is unknown too', () async {
      responder = (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );

      await expectLater(
        service().decline(7, 'Cannot supply this request'),
        throwsA(
          isA<RequisitionServiceException>().having(
            (e) => e.outcomeUnknown,
            'outcomeUnknown',
            isTrue,
          ),
        ),
      );
    });

    test('a 400 refusal IS an answer, so nothing is left unknown', () async {
      // The server said no and wrote nothing: offering the corrected decision again is
      // exactly what staff should be able to do.
      responder = (_) => _json({
        'items': ['Every line needs an answer.'],
      }, status: 400);

      await expectLater(
        service().accept(7, const [
          RequisitionLineDecision(lineId: 21, available: true),
        ]),
        throwsA(
          isA<RequisitionServiceException>().having(
            (e) => e.outcomeUnknown,
            'outcomeUnknown',
            isFalse,
          ),
        ),
      );
    });

    test('a stale 409 is an answer too, and keeps its code', () async {
      responder = (_) => _json({
        'code': 'REQUEST_ALREADY_REVIEWED',
        'detail': 'Already reviewed.',
      }, status: 409);

      await expectLater(
        service().decline(7, 'Cannot supply this request'),
        throwsA(
          isA<RequisitionServiceException>()
              .having((e) => e.outcomeUnknown, 'outcomeUnknown', isFalse)
              .having((e) => e.code, 'code', 'REQUEST_ALREADY_REVIEWED'),
        ),
      );
    });
  });

  // Phase 1b Task 7 review round 1: a decision is STORED before its answer comes back, so a
  // 200 this build cannot read is the opposite of a refusal. Reading it as one re-offers
  // Accept/Decline on a request that may already have an answer.
  group('an unreadable 200 is an unknown WRITE outcome', () {
    const decisions = [RequisitionLineDecision(lineId: 21, available: true)];
    final unknown = throwsA(
      isA<RequisitionServiceException>().having(
        (e) => e.outcomeUnknown,
        'outcomeUnknown',
        isTrue,
      ),
    );

    test(
      'an accept answer missing its keys is unknown, not a refusal',
      () async {
        responder = (_) => _json({'id': 7});
        await expectLater(service().accept(7, decisions), unknown);
      },
    );

    test('a decline answer with an empty body is unknown too', () async {
      responder = (_) => ResponseBody.fromString(
        '',
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
      await expectLater(
        service().decline(7, 'Cannot supply this request'),
        unknown,
      );
    });

    test('an answer whose JSON types drifted is unknown too', () async {
      // `items` as a string is a TypeError inside the parser rather than a FormatException,
      // and it used to escape the service entirely: the screen read it as "could not be sent"
      // and offered the same decision again.
      responder = (_) => _json({'id': 7, 'items': 'not-a-list'});
      await expectLater(service().accept(7, decisions), unknown);
    });

    test('a READ keeps reading a drifted body as a plain failure', () async {
      // The unknown-outcome flag belongs to WRITES: nothing was stored by a GET, so asking
      // the same question again is exactly right.
      responder = (_) => _json({'id': 7});
      await expectLater(
        service().fetchRequisition(7),
        throwsA(
          isA<RequisitionServiceException>().having(
            (e) => e.outcomeUnknown,
            'outcomeUnknown',
            isFalse,
          ),
        ),
      );
    });
  });
}
