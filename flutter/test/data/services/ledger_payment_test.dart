import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/services/ledger_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  ResponseBody Function(RequestOptions options) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
);

void main() {
  late _FakeAdapter adapter;
  late LedgerService service;
  final captured = <RequestOptions>[];

  setUpAll(() {
    ApiClient.instance.init();
  });

  setUp(() {
    captured.clear();
    adapter = _FakeAdapter((options) {
      captured.add(options);
      return _json({'id': 11}, status: 201);
    });
    ApiClient.instance.dio.httpClientAdapter = adapter;
    service = LedgerService();
  });

  test('a payment posts the ledger id and amount to ledger-payments', () async {
    await service.recordPayment(collectibleId: 7, amountPaid: 472);

    expect(captured, hasLength(1));
    expect(captured.single.method, 'POST');
    expect(captured.single.path, '/api/v1/ledger-payments/');
    expect(captured.single.data, {
      'collectible': 7,
      'amount_paid': 472,
      'payment_method': 'CASH',
    });
  });

  test('an overpayment reports the server refusal, not a generic failure', () async {
    adapter.respond = (_) => _json({
      'code': 'PAYMENT_EXCEEDS_BALANCE',
      'detail': 'That payment of 500.00 is more than the 472.00 still owed on this account.',
      'balance_due': '472.00',
    }, status: 400);

    await expectLater(
      service.recordPayment(collectibleId: 7, amountPaid: 500),
      throwsA(isA<LedgerServiceException>().having(
        (e) => e.message,
        'message',
        contains('more than the 472.00 still owed'),
      )),
    );
  });

  test('a refused session reports sign-in, not a payment failure', () async {
    adapter.respond = (_) => _json({'detail': 'Authentication required.'}, status: 401);

    await expectLater(
      service.recordPayment(collectibleId: 7, amountPaid: 100),
      throwsA(isA<LedgerServiceException>().having(
        (e) => e.message,
        'message',
        'Your session has expired. Sign in again.',
      )),
    );
  });
}
