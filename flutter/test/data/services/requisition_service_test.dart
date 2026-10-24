// Phase 5 (decision 09, locked 2026-10-17): POS builds the DOWNSTREAM half of the requisition
// lifecycle — approve, reject, verify token, release. CPMS owns create and submit.
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
    if (adapter.replaced != null) client.dio.httpClientAdapter = adapter.replaced!;
  });

  RequisitionService service() => RequisitionService(client: client);

  test('reads a requisition with its items, and a NULL token on a not-yet-approved row', () async {
    serve((_) => _json({'count': 1, 'next': null, 'results': [_requisition()]}));

    final rows = await service().fetchRequisitions();

    expect(rows, hasLength(1));
    final req = rows.single;
    expect(req.reqNumber, 'REQ-20260925-0002');
    expect(req.status, RequisitionStatus.submitted);
    expect(req.projectName, '2-Storey House - Mandaue');
    expect(req.projectCustomerName, 'Dela Cruz Construction');
    expect(req.requestedByName, 'Fore Man');
    expect(req.token, isNull, reason: 'SUBMITTED has no token yet - verified live');
    expect(req.items, hasLength(1));
    expect(req.items.single.variantName, '1/2 inch x 3m');
    expect(req.items.single.quantity, 4);
    expect(req.items.single.releasedQty, 0);
  });

  test('a status the client does not know is kept, not dropped', () async {
    // A new server status must not make the row vanish from the queue or read as DRAFT - the
    // queue's whole job is to show what is waiting.
    serve((_) => _json({'count': 1, 'next': null, 'results': [_requisition(status: 'ON_HOLD')]}));

    final req = (await service().fetchRequisitions()).single;
    expect(req.status, RequisitionStatus.unknown);
    expect(req.rawStatus, 'ON_HOLD', reason: 'the cashier can still be shown what it really is');
  });

  test('follows the pages, so a long queue is not silently cut off', () async {
    final pages = <String>[];
    serve((options) {
      pages.add('${options.queryParameters['page']}');
      if (options.queryParameters['page'] == 1) {
        return _json({'count': 2, 'next': 'http://x/api/v1/requisitions/?page=2',
                      'results': [_requisition(id: 1, reqNumber: 'REQ-1')]});
      }
      return _json({'count': 2, 'next': null,
                    'results': [_requisition(id: 2, reqNumber: 'REQ-2')]});
    });

    final rows = await service().fetchRequisitions();

    expect(rows.map((r) => r.reqNumber), ['REQ-1', 'REQ-2']);
    expect(pages, ['1', '2']);
  });

  test('approving returns the token the server minted', () async {
    serve((options) {
      expect(options.path, endsWith('/requisitions/2/approve/'));
      return _json({'detail': 'REQ-20260925-0002 approved.',
                    'token': 'd5a4eb1f-0e88-497d-bc3b-688b14a6a867'});
    });

    final token = await service().approve(2);

    expect(token, 'd5a4eb1f-0e88-497d-bc3b-688b14a6a867');
  });

  test('a refused transition surfaces the SERVER message, not a generic one', () async {
    // The server refuses an illegal move with prose naming the reason ("Cannot approve a
    // SUBMITTED requisition."). Replacing it with "something went wrong" throws away the only
    // information the manager has about why the button did nothing.
    serve((_) => _json({'detail': 'Cannot approve a DRAFT requisition.'}, status: 400));

    await expectLater(
      service().approve(2),
      throwsA(isA<RequisitionServiceException>().having(
        (e) => e.message, 'message', 'Cannot approve a DRAFT requisition.')),
    );
  });

  test('verifying a token returns the requisition and each item with what REMAINS', () async {
    serve((options) {
      expect(options.path, endsWith('/tokens/verify/'));
      return _json({
        'token': 'd5a4eb1f-0e88-497d-bc3b-688b14a6a867',
        'requisition': {
          'id': 3, 'req_number': 'REQ-20260925-0003',
          'project': '2-Storey House - Mandaue', 'customer': 'Dela Cruz Construction',
        },
        'items': [
          {'id': 31, 'variant_id': 4, 'variant_name': '1/2 inch x 3m',
           'quantity': '4.00', 'remaining': '4.00'},
        ],
      });
    });

    final verified = await service().verifyToken('d5a4eb1f-0e88-497d-bc3b-688b14a6a867');

    expect(verified.reqNumber, 'REQ-20260925-0003');
    expect(verified.project, '2-Storey House - Mandaue');
    expect(verified.customer, 'Dela Cruz Construction');
    expect(verified.items.single.remaining, 4);
  });

  test('a USED token reads as already used, which is not the same as not found', () async {
    // The two must stay distinguishable: "not found" makes a cashier think they mistyped and try
    // again, while the token has in fact already released the goods.
    serve((_) => _json({'detail': 'Token has already been used.'}, status: 400));

    await expectLater(
      service().verifyToken('d5a4eb1f-0e88-497d-bc3b-688b14a6a867'),
      throwsA(isA<RequisitionServiceException>().having(
        (e) => e.message, 'message', 'Token has already been used.')),
    );
  });

  test('releasing returns the sale it created, and the receivable it posted', () async {
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

    final result = await service().release('d5a4eb1f-0e88-497d-bc3b-688b14a6a867');

    expect(result.transactionNo, 'TRX-20261017-0001');
    expect(result.grandTotal, 1260);
    expect(result.ledgerId, 4, reason: 'a construction firm pays later, so a ledger is always posted');
    expect(result.balanceDue, 1260);
  });

  test('insufficient stock on release is reported as a stock problem', () async {
    serve((_) => _json({'detail': 'Insufficient stock for 1/2 inch x 3m.'}, status: 400));

    await expectLater(
      service().release('d5a4eb1f-0e88-497d-bc3b-688b14a6a867'),
      throwsA(isA<RequisitionServiceException>().having(
        (e) => e.message, 'message', contains('Insufficient stock'))),
    );
  });

  // Phase 1 Task 6 (audit remediation): `release_materials` now refuses a variant that has no
  // conversion-factor-1 selling unit, because the old fallback priced the line at zero and
  // handed `variant_uom=None` to a non-null FK — a half-written sale. The 400 carries
  // `{code: NO_BASE_UOM, detail: "Variant ... has no base-unit selling price ..."}`, which a
  // clerk can only act on if the screen says WHAT to fix, so the detail must survive.
  test('NO_BASE_UOM tells the clerk which catalogue gap blocks the release', () async {
    serve((_) => _json({
      'code': 'NO_BASE_UOM',
      'detail': 'Variant 12 - 1/2 inch x 3m has no base-unit selling price: add a '
          'selling unit with conversion factor 1 before releasing it.',
    }, status: 400));

    await expectLater(
      service().release('d5a4eb1f-0e88-497d-bc3b-688b14a6a867'),
      throwsA(isA<RequisitionServiceException>().having(
        (e) => e.message,
        'message',
        startsWith('The release was refused: this material has no base unit in '
            'the catalogue.'),
      )),
    );
  });

  test('an unreachable server says so in words a cashier can act on', () async {
    serve((options) => throw DioException(
      requestOptions: options, type: DioExceptionType.connectionError));

    await expectLater(
      service().fetchRequisitions(),
      throwsA(isA<RequisitionServiceException>().having(
        (e) => e.message, 'message', 'Cannot connect to the BuildPro server.')),
    );
  });
}
