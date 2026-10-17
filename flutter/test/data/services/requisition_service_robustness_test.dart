// Phase 5 review findings 1 and 2 (2026-10-17): what the service does when the wire is not what it
// expects. Kept in its own file rather than appended to requisition_service_test.dart, because the
// existing suite's shape is the happy path and these are the two ways it goes wrong.
import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/services/requisition_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);
  final ResponseBody Function(RequestOptions options) respond;
  HttpClientAdapter? replaced;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? s, Future<void>? c) async =>
      respond(options);

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
    if (adapter.replaced != null) client.dio.httpClientAdapter = adapter.replaced!;
  });

  test('a DRIFTED success body reports a service error, not a raw parse crash', () async {
    // The server answered 200 but its shape moved: verify's parser needs keys that are absent.
    // Before the fix this threw a bare FormatException, which the viewmodel never catches - so
    // verify silently did nothing and release left its spinner running forever.
    responder = (options) => _json({'token': 'a-token'});
    await expectLater(
      service().verifyToken('a-token'),
      throwsA(isA<RequisitionServiceException>()),
    );
  });

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
}
