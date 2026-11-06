// Decision 01 (locked 2026-11-03): the POS reads approved requisitions and releases
// materials against a token. CPMS creates, approves, rejects and closes them, so this
// service has no write on the request itself.
//
// The wire shapes here were read from backend_django/apps/requisitions/{serializers,services}.py
// and PROBED live, not guessed. Two facts the probe settled:
//
//   * `token` is null on DRAFT/SUBMITTED requisitions (the reverse OneToOne does not exist yet).
//     A regular DRF field renders None there, where a ReadOnlyField would SKIP the key entirely -
//     the difference that made customer_name a KeyError in the collectibles serializer.
//   * verify and release are DIFFERENT shapes: verify returns the requisition for display, release
//     returns the transaction it created. Release also always posts a receivable, because a
//     construction firm pays later.

import 'dart:convert';
import 'dart:io';

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
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
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

Map<String, dynamic> _requisition({
  int id = 2,
  String reqNumber = 'REQ-20260925-0002',
  String status = 'SUBMITTED',
  String? token,
}) => {
  'id': id,
  'project': 1,
  'project_name': '2-Storey House - Mandaue',
  'project_customer_name': 'Dela Cruz Construction',
  'req_number': reqNumber,
  'requested_by': 5,
  'requested_by_name': 'Fore Man',
  'approved_by': null,
  'status': status,
  'notes': '',
  'items': [
    {
      'id': 21,
      'requisition': id,
      'variant': 4,
      'variant_name': '1/2 inch x 3m',
      'quantity': '4.00',
      'released_qty': '0.00',
      'notes': '',
    },
  ],
  'token': token,
  'created_at': '2026-09-25T08:00:00+08:00',
  'updated_at': '2026-09-25T08:00:00+08:00',
};

void main() {
  late ApiClient client;
  late _FakeAdapter adapter;

  setUpAll(() {
    // init() is NOT idempotent (dio is `late final`), so it happens once and only the adapter
    // is swapped per test.
    client = ApiClient.instance..init();
  });

  void serve(ResponseBody Function(RequestOptions options) respond) {
    adapter = _FakeAdapter(respond);
    adapter.replaced = client.dio.httpClientAdapter;
    client.dio.httpClientAdapter = adapter;
  }

  tearDown(() {
    if (adapter.replaced != null) {
      client.dio.httpClientAdapter = adapter.replaced!;
    }
  });

  RequisitionService service() => RequisitionService(client: client);

  test(
    'reads a requisition with its items, and a NULL token on a not-yet-approved row',
    () async {
      serve(
        (_) => _json({
          'count': 1,
          'next': null,
          'results': [_requisition()],
        }),
      );

      final rows = await service().fetchRequisitions();

      expect(rows, hasLength(1));
      final req = rows.single;
      expect(req.reqNumber, 'REQ-20260925-0002');
      expect(req.status, RequisitionStatus.submitted);
      expect(req.projectName, '2-Storey House - Mandaue');
      expect(req.projectCustomerName, 'Dela Cruz Construction');
      expect(req.requestedByName, 'Fore Man');
      expect(
        req.token,
        isNull,
        reason: 'SUBMITTED has no token yet - verified live',
      );
      expect(req.items, hasLength(1));
      expect(req.items.single.variantName, '1/2 inch x 3m');
      expect(req.items.single.quantity, 4);
      expect(req.items.single.releasedQty, 0);
    },
  );

  test('a status the client does not know is kept, not dropped', () async {
    // A new server status must not make the row vanish from the queue or read as DRAFT - the
    // queue's whole job is to show what is waiting.
    serve(
      (_) => _json({
        'count': 1,
        'next': null,
        'results': [_requisition(status: 'ON_HOLD')],
      }),
    );

    final req = (await service().fetchRequisitions()).single;
    expect(req.status, RequisitionStatus.unknown);
    expect(
      req.rawStatus,
      'ON_HOLD',
      reason: 'the cashier can still be shown what it really is',
    );
  });

  test('follows the pages, so a long queue is not silently cut off', () async {
    final pages = <String>[];
    serve((options) {
      pages.add('${options.queryParameters['page']}');
      if (options.queryParameters['page'] == 1) {
        return _json({
          'count': 2,
          'next': 'http://x/api/v1/requisitions/?page=2',
          'results': [_requisition(id: 1, reqNumber: 'REQ-1')],
        });
      }
      return _json({
        'count': 2,
        'next': null,
        'results': [_requisition(id: 2, reqNumber: 'REQ-2')],
      });
    });

    final rows = await service().fetchRequisitions();

    expect(rows.map((r) => r.reqNumber), ['REQ-1', 'REQ-2']);
    expect(pages, ['1', '2']);
  });

  // Decision 01 (2026-11-03): requests are created and approved in CPMS, so
  // the POS service has no approve and no reject call to offer. The server
  // answers 405/404 on those paths now (backend Task 4), and a client method
  // that still points at them is a button that can only fail.
  test('the service no longer knows an approve or reject path', () {
    final source = File(
      'lib/data/services/requisition_service.dart',
    ).readAsStringSync();

    expect(source, isNot(contains('/approve/')));
    expect(source, isNot(contains('/reject/')));
    expect(source, isNot(contains('Future<String> approve')));
    expect(source, isNot(contains('Future<void> reject')));
  });

  test(
    'verifying a token returns the requisition and each item with what REMAINS',
    () async {
      serve((options) {
        expect(options.path, endsWith('/tokens/verify/'));
        return _json({
          'token': 'd5a4eb1f-0e88-497d-bc3b-688b14a6a867',
          'requisition': {
            'id': 3,
            'req_number': 'REQ-20260925-0003',
            'project': '2-Storey House - Mandaue',
            'customer': 'Dela Cruz Construction',
          },
          'items': [
            {
              'id': 31,
              'variant_id': 4,
              'variant_name': '1/2 inch x 3m',
              'quantity': '4.00',
              'remaining': '4.00',
            },
          ],
        });
      });

      final verified = await service().verifyToken(
        'd5a4eb1f-0e88-497d-bc3b-688b14a6a867',
      );

      expect(verified.reqNumber, 'REQ-20260925-0003');
      expect(verified.project, '2-Storey House - Mandaue');
      expect(verified.customer, 'Dela Cruz Construction');
      expect(verified.items.single.remaining, 4);
    },
  );

  test(
    'a USED token reads as already used, which is not the same as not found',
    () async {
      // The two must stay distinguishable: "not found" makes a cashier think they mistyped and try
      // again, while the token has in fact already released the goods.
      serve(
        (_) => _json({'detail': 'Token has already been used.'}, status: 400),
      );

      await expectLater(
        service().verifyToken('d5a4eb1f-0e88-497d-bc3b-688b14a6a867'),
        throwsA(
          isA<RequisitionServiceException>().having(
            (e) => e.message,
            'message',
            'Token has already been used.',
          ),
        ),
      );
    },
  );

  test(
    'releasing returns the sale it created, and the receivable it posted',
    () async {
      serve((options) {
        expect(options.path, endsWith('/tokens/release/'));
        return _json({
          'transaction_id': 14,
          'transaction_no': 'TRX-20261017-0001',
          'grand_total': '1260.00',
          'ledger_id': 4,
          'balance_due': '1260.00',
        }, status: 201);
      });

      final result = await service().release(
        'd5a4eb1f-0e88-497d-bc3b-688b14a6a867',
      );

      expect(result.transactionNo, 'TRX-20261017-0001');
      expect(result.grandTotal, 1260);
      expect(
        result.ledgerId,
        4,
        reason: 'a construction firm pays later, so a ledger is always posted',
      );
      expect(result.balanceDue, 1260);
    },
  );

  test(
    'insufficient stock on release is reported as a stock problem',
    () async {
      serve(
        (_) => _json({
          'detail': 'Insufficient stock for 1/2 inch x 3m.',
        }, status: 400),
      );

      await expectLater(
        service().release('d5a4eb1f-0e88-497d-bc3b-688b14a6a867'),
        throwsA(
          isA<RequisitionServiceException>().having(
            (e) => e.message,
            'message',
            contains('Insufficient stock'),
          ),
        ),
      );
    },
  );

  // Decision 01 removed every POS-side approval, and with it the codes those actions
  // refused with (SELF_APPROVAL, REQUISITION_LOCKED). The backend no longer emits
  // NO_BASE_UOM either (Phase 1 Task 5 deleted the pricing fallback it guarded), so the
  // client keeps no mapping for a code nobody sends.
  test('an unreachable server says so in words a cashier can act on', () async {
    serve(
      (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      ),
    );

    await expectLater(
      service().fetchRequisitions(),
      throwsA(
        isA<RequisitionServiceException>().having(
          (e) => e.message,
          'message',
          'Cannot connect to the BuildPro server.',
        ),
      ),
    );
  });

  // Phase 1, Task 9 (decision 05): the shelf can be short, and a short shelf no longer
  // refuses the whole release. So the token check has to carry, per line, what can leave
  // the store NOW, and the release answer has to say what this scan moved and what is
  // still owed on the token.
  test('verifying a token reads what can leave the store per line', () async {
    serve(
      (_) => _json({
        'token': 'd5a4eb1f-0e88-497d-bc3b-688b14a6a867',
        'requisition': {
          'id': 3,
          'req_number': 'REQ-20260925-0003',
          'project': '2-Storey House - Mandaue',
          'customer': 'Dela Cruz Construction',
        },
        'items': [
          {
            'id': 31,
            'variant_id': 4,
            'variant_name': '1/2 inch x 3m',
            'quantity': '10.00',
            'remaining': '10.00',
            'availability': 'SHORT',
            'releasable': '4.00',
          },
          {
            'id': 32,
            'variant_id': 5,
            'variant_name': 'Marine Plywood 3/4 in',
            'quantity': '24.00',
            'remaining': '0.00',
            'availability': 'DONE',
            'releasable': '0.00',
          },
        ],
      }),
    );

    final verified = await service().verifyToken(
      'd5a4eb1f-0e88-497d-bc3b-688b14a6a867',
    );

    expect(verified.items.first.availability, LineAvailability.short);
    expect(verified.items.first.goesNow, 4);
    expect(verified.items.first.outstanding, 6);
    expect(verified.items.last.availability, LineAvailability.done);
  });

  test(
    'releasing reports PARTIAL and the lines still open on the token',
    () async {
      serve(
        (_) => _json({
          'transaction_id': 14,
          'transaction_no': 'TRX-20261017-0001',
          'req_number': 'REQ-20260925-0003',
          'status': 'PARTIAL',
          'items': [
            {'code': 'CEM-40', 'released_now': '10.00', 'outstanding': '0.00'},
            {'code': 'STL-10', 'released_now': '4.00', 'outstanding': '6.00'},
          ],
          'grand_total': '1260.00',
          'ledger_id': 4,
          'balance_due': '1260.00',
        }, status: 201),
      );

      final result = await service().release(
        'd5a4eb1f-0e88-497d-bc3b-688b14a6a867',
      );

      expect(result.status, ReleaseStatus.partial);
      expect(result.isPartial, isTrue);
      expect(result.openLineCount, 1);
    },
  );

  // Decision 05: `NOTHING_TO_RELEASE` is a FACT about the shelf, not a failure, and the
  // server's detail is written for a developer. The till answers with its own words so a
  // clerk knows the token still works once stock arrives.
  test('NOTHING_TO_RELEASE is answered in the cashier\'s words', () async {
    serve(
      (_) => _json({
        'code': 'NOTHING_TO_RELEASE',
        'detail':
            'Nothing on this request can be released: every line is short, '
            'out of stock or unavailable. The token stays valid.',
      }, status: 400),
    );

    await expectLater(
      service().release('d5a4eb1f-0e88-497d-bc3b-688b14a6a867'),
      throwsA(
        isA<RequisitionServiceException>()
            .having((e) => e.code, 'code', 'NOTHING_TO_RELEASE')
            .having(
              (e) => e.message,
              'message',
              'Nothing on this request is in stock right now. '
                  'Try the same token again after the next delivery.',
            ),
      ),
    );
  });

  test(
    'a CLOSED request tells the clerk to ask the project for a new one',
    () async {
      // Keyed on the stable code: the detail below is deliberately reworded prose.
      serve(
        (_) => _json({
          'code': 'REQUISITION_CLOSED',
          'detail': 'Server wording that may change.',
        }, status: 400),
      );

      await expectLater(
        service().release('d5a4eb1f-0e88-497d-bc3b-688b14a6a867'),
        throwsA(
          isA<RequisitionServiceException>().having(
            (e) => e.message,
            'message',
            'This request was closed in the project system. '
                'Ask the project to send a new one.',
          ),
        ),
      );
    },
  );

  test(
    'an already RELEASED request says nothing is left on the token',
    () async {
      serve(
        (_) => _json({
          'code': 'REQUISITION_RELEASED',
          'detail': 'Server wording that may change.',
        }, status: 400),
      );

      await expectLater(
        service().release('d5a4eb1f-0e88-497d-bc3b-688b14a6a867'),
        throwsA(
          isA<RequisitionServiceException>().having(
            (e) => e.message,
            'message',
            'Everything on this request was already released. '
                'There is nothing left to hand over.',
          ),
        ),
      );
    },
  );

  test('a CANCELLED request says nothing may be released for it', () async {
    serve(
      (_) => _json({
        'code': 'REQUISITION_CANCELLED',
        'detail': 'Server wording that may change.',
      }, status: 400),
    );

    await expectLater(
      service().release('d5a4eb1f-0e88-497d-bc3b-688b14a6a867'),
      throwsA(
        isA<RequisitionServiceException>().having(
          (e) => e.message,
          'message',
          'This request was cancelled in the project system, so nothing can '
              'be released for it.',
        ),
      ),
    );
  });

  test(
    'a status refusal this client was not taught keeps the server\'s words',
    () async {
      // Only the three dead-end statuses get client copy. A DRAFT refusal still explains
      // itself better in the server's sentence than in anything this file could invent.
      serve(
        (_) => _json({
          'detail': 'Requisition is DRAFT, not APPROVED or PARTIAL.',
        }, status: 400),
      );

      await expectLater(
        service().release('d5a4eb1f-0e88-497d-bc3b-688b14a6a867'),
        throwsA(
          isA<RequisitionServiceException>().having(
            (e) => e.message,
            'message',
            'Requisition is DRAFT, not APPROVED or PARTIAL.',
          ),
        ),
      );
    },
  );
}
