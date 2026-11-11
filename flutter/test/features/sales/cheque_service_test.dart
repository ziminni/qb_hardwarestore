// Phase 4 F5: the cheque queue's wire contract.
//
// Shapes below are trimmed copies of the REAL `ChequeSerializer` and of the
// `POST /ledger-payments/` CHEQUE branch (backend B2, decision 18), so a field
// rename on the server fails here instead of rendering a blank queue.
//
// The refusals matter as much as the happy path: a cashier/manager must never
// see "already decided" flattened into "something went wrong", and a server
// detail the client does not recognise must reach the screen verbatim.

import 'dart:convert';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/cheque.dart';
import 'package:client/data/services/cheque_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _chequesPath = '/api/v1/cheques/';
const _ledgerPaymentsPath = '/api/v1/ledger-payments/';

Map<String, dynamic> _envelope(List<Map<String, dynamic>> results) => {
  'count': results.length,
  'next': null,
  'previous': null,
  'results': results,
};

Map<String, dynamic> _cheque({
  int id = 7,
  String status = 'PENDING',
  String amount = '15.00',
  String chequeDate = '2026-11-20',
  String? reason,
  String? decidedAt,
}) => {
  'id': id,
  'transaction': 18,
  'transaction_no': 'TRX-20261016-0007',
  'customer': 2,
  'customer_name': 'Dela Cruz Construction',
  'ledger': 4,
  'amount': amount,
  'cheque_number': 'CHQ-1001',
  'bank': 'BDO',
  'cheque_date': chequeDate,
  'status': status,
  'reference_no': '',
  'received_at': '2026-10-16T18:56:59.912001+08:00',
  'decided_by': decidedAt == null ? null : 1,
  'decided_by_name': decidedAt == null ? null : 'Ada Ministrator',
  'decided_at': decidedAt,
  'decision_reason': reason,
};

/// One canned answer per path, with the status code the server would send.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.bodies, {this.statusCode = 200});

  final Map<String, Object?> bodies;
  final int statusCode;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (!bodies.containsKey(options.path)) {
      return ResponseBody.fromString(
        '{"detail":"not found"}',
        404,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(bodies[options.path]),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Answers page N of one list endpoint, so the paging walk can be observed.
class _PagedAdapter implements HttpClientAdapter {
  _PagedAdapter(this.pages);

  final List<Map<String, dynamic>> pages;
  final List<String?> requestedPages = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final page = int.parse(options.queryParameters['page']?.toString() ?? '1');
    requestedPages.add(options.queryParameters['page']?.toString());
    final body = pages[page - 1 < pages.length ? page - 1 : pages.length - 1];
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late ApiClient client;

  // `ApiClient.init()` assigns a `late final dio`, so it is NOT idempotent.
  setUpAll(() => client = ApiClient.instance..init());

  ChequeService service() => ChequeService(client: client);

  test('parses a queue row, including the ledger it is waiting on', () async {
    client.dio.httpClientAdapter = _FakeAdapter({
      _chequesPath: _envelope([_cheque()]),
    });

    final rows = await service().fetchCheques();

    expect(rows, hasLength(1));
    final cheque = rows.single;
    expect(cheque.id, 7);
    expect(cheque.transactionNo, 'TRX-20261016-0007');
    expect(cheque.customerName, 'Dela Cruz Construction');
    expect(cheque.ledgerId, 4);
    expect(cheque.amount, 15);
    expect(cheque.chequeNumber, 'CHQ-1001');
    expect(cheque.bank, 'BDO');
    expect(cheque.chequeDate, DateTime(2026, 11, 20));
    expect(cheque.status, ChequeStatus.pending);
    expect(cheque.isPending, isTrue);
    expect(cheque.decidedAt, isNull);
  });

  test(
    'reads every page: a cheque past row 50 is still in the queue',
    () async {
      final paged = _PagedAdapter([
        {
          'count': 2,
          'next': 'http://test$_chequesPath?page=2',
          'previous': null,
          'results': [_cheque(id: 1)],
        },
        {
          'count': 2,
          'next': null,
          'previous': 'http://test$_chequesPath?page=1',
          'results': [_cheque(id: 2)],
        },
      ]);
      client.dio.httpClientAdapter = paged;

      final rows = await service().fetchCheques();

      expect(rows.map((row) => row.id).toList(), [1, 2]);
      expect(paged.requestedPages, ['1', '2']);
    },
  );

  test('a decided row carries who decided it and why', () async {
    client.dio.httpClientAdapter = _FakeAdapter({
      _chequesPath: _envelope([
        _cheque(
          status: 'BOUNCED',
          reason: 'Insufficient funds',
          decidedAt: '2026-11-21T09:00:00+08:00',
        ),
      ]),
    });

    final cheque = (await service().fetchCheques()).single;

    expect(cheque.status, ChequeStatus.bounced);
    expect(cheque.decidedByName, 'Ada Ministrator');
    expect(cheque.decisionReason, 'Insufficient funds');
  });

  test(
    'a status the client cannot render fails loudly, not silently',
    () async {
      client.dio.httpClientAdapter = _FakeAdapter({
        _chequesPath: _envelope([_cheque(status: 'ESCROWED')]),
      });

      await expectLater(
        service().fetchCheques(),
        throwsA(
          isA<ChequeServiceException>().having(
            (error) => error.message,
            'message',
            contains('could not be read'),
          ),
        ),
      );
    },
  );

  test('clear posts to the cheque and answers the updated row', () async {
    final adapter = _FakeAdapter({
      '${_chequesPath}7/clear/': _cheque(
        status: 'CLEARED',
        decidedAt: '2026-11-21T09:00:00+08:00',
      ),
    });
    client.dio.httpClientAdapter = adapter;

    final cleared = await service().clear(7);

    expect(cleared.status, ChequeStatus.cleared);
    final request = adapter.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.path, '${_chequesPath}7/clear/');
  });

  test('bounce sends the reason and answers the updated row', () async {
    final adapter = _FakeAdapter({
      '${_chequesPath}7/bounce/': _cheque(
        status: 'BOUNCED',
        reason: 'Insufficient funds',
        decidedAt: '2026-11-21T09:00:00+08:00',
      ),
    });
    client.dio.httpClientAdapter = adapter;

    final bounced = await service().bounce(7, 'Insufficient funds');

    expect(bounced.status, ChequeStatus.bounced);
    expect(bounced.decisionReason, 'Insufficient funds');
    expect(adapter.requests.single.data, {'reason': 'Insufficient funds'});
  });

  test('a second decision keeps the server detail and its 409 code', () async {
    client.dio.httpClientAdapter = _FakeAdapter({
      '${_chequesPath}7/clear/': {
        'code': 'CHEQUE_ALREADY_DECIDED',
        'detail': 'CHQ-1001 is already bounced and cannot be decided again.',
        'status': 'BOUNCED',
      },
    }, statusCode: 409);

    await expectLater(
      service().clear(7),
      throwsA(
        isA<ChequeServiceException>()
            .having((error) => error.code, 'code', 'CHEQUE_ALREADY_DECIDED')
            .having(
              (error) => error.message,
              'message',
              'CHQ-1001 is already bounced and cannot be decided again.',
            ),
      ),
    );
  });

  test('a bounce without a reason keeps the server sentence', () async {
    client.dio.httpClientAdapter = _FakeAdapter({
      '${_chequesPath}7/bounce/': {
        'code': 'CHEQUE_REASON_REQUIRED',
        'detail': 'A bounced cheque needs a reason.',
      },
    }, statusCode: 400);

    await expectLater(
      service().bounce(7, '  '),
      throwsA(
        isA<ChequeServiceException>()
            .having((error) => error.code, 'code', 'CHEQUE_REASON_REQUIRED')
            .having(
              (error) => error.message,
              'message',
              'A bounced cheque needs a reason.',
            ),
      ),
    );
  });

  test('an unrecognised refusal still shows the server detail', () async {
    client.dio.httpClientAdapter = _FakeAdapter({
      '${_chequesPath}7/clear/': {
        'code': 'PAYMENT_EXCEEDS_BALANCE',
        'detail':
            'That utang was settled in cash while this cheque was pending.',
      },
    }, statusCode: 400);

    await expectLater(
      service().clear(7),
      throwsA(
        isA<ChequeServiceException>().having(
          (error) => error.message,
          'message',
          'That utang was settled in cash while this cheque was pending.',
        ),
      ),
    );
  });

  test('a 403 says the queue is not this account\'s', () async {
    client.dio.httpClientAdapter = _FakeAdapter({
      '${_chequesPath}7/clear/': {'detail': 'You do not have permission.'},
    }, statusCode: 403);

    await expectLater(
      service().clear(7),
      throwsA(
        isA<ChequeServiceException>().having(
          (error) => error.message,
          'message',
          'You do not have access to cheques.',
        ),
      ),
    );
  });

  test(
    'a utang cheque posts the CHEQUE tender and answers a pending cheque',
    () async {
      final adapter = _FakeAdapter({
        _ledgerPaymentsPath: _cheque(amount: '15.00'),
      }, statusCode: 201);
      client.dio.httpClientAdapter = adapter;

      final cheque = await service().recordChequeAgainstLedger(
        collectibleId: 4,
        amount: 15,
        chequeNumber: 'CHQ-1001',
        bank: 'BDO',
        chequeDate: DateTime(2026, 11, 20),
      );

      expect(cheque.status, ChequeStatus.pending);
      expect(adapter.requests.single.data, {
        'collectible': 4,
        'amount_paid': 15.0,
        'payment_method': 'CHEQUE',
        'cheque_number': 'CHQ-1001',
        'bank': 'BDO',
        'cheque_date': '2026-11-20',
      });
    },
  );

  test(
    'a cheque above the utang keeps PAYMENT_EXCEEDS_BALANCE wording',
    () async {
      client.dio.httpClientAdapter = _FakeAdapter({
        _ledgerPaymentsPath: {
          'code': 'PAYMENT_EXCEEDS_BALANCE',
          'detail': 'That payment is more than the 472.00 still owed.',
        },
      }, statusCode: 400);

      await expectLater(
        service().recordChequeAgainstLedger(
          collectibleId: 4,
          amount: 500,
          chequeNumber: 'CHQ-1001',
          bank: 'BDO',
          chequeDate: DateTime(2026, 11, 20),
        ),
        throwsA(
          isA<ChequeServiceException>().having(
            (error) => error.message,
            'message',
            'That payment is more than the 472.00 still owed.',
          ),
        ),
      );
    },
  );

  test('a walk-in refusal keeps the server sentence', () async {
    client.dio.httpClientAdapter = _FakeAdapter({
      _ledgerPaymentsPath: {
        'code': 'CHEQUE_NEEDS_CUSTOMER',
        'detail':
            'A cheque needs a named customer. Walk-in Customer is a walk-in.',
      },
    }, statusCode: 400);

    await expectLater(
      service().recordChequeAgainstLedger(
        collectibleId: 4,
        amount: 15,
        chequeNumber: 'CHQ-1001',
        bank: 'BDO',
        chequeDate: DateTime(2026, 11, 20),
      ),
      throwsA(
        isA<ChequeServiceException>().having(
          (error) => error.message,
          'message',
          'A cheque needs a named customer. Walk-in Customer is a walk-in.',
        ),
      ),
    );
  });
}
