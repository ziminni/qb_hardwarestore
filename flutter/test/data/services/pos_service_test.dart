// Phase 3 Task 3 (decision 06, sections 1 and 2): the checkout call.
//
// The response shape below is a trimmed copy of the REAL SalesTransactionSerializer,
// verified 2026-10-16 against backend_django/apps/pos/serializers.py: the response IS
// the finished transaction, with `items`, `payments` and `receipt` nested read-only
// children. Decision 06 turns on that: the receipt screen needs NO second fetch, so a
// test that let the client re-fetch by id would be encoding the wrong contract.
//
// The error shapes are equally deliberate. Decision 06 section 3 requires the client to
// tell "not enough stock" apart from "the server broke", which is only possible because
// the backend now publishes INSUFFICIENT_STOCK as a 400 with a code.

import 'dart:convert';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _transactionsPath = '/api/v1/transactions/';

/// The finished transaction, shaped like the real serializer.
Map<String, dynamic> _transaction({String grandTotal = '20.00'}) => {
  'id': 18,
  'customer': 2,
  'customer_name': 'Walk-in Customer',
  'cashier': 1,
  'cashier_name': 'Ada Ministrator',
  'transaction_no': 'TRX-20261016-0007',
  'trans_date': '2026-10-16T18:56:59.912001+08:00',
  'vatable_sales': grandTotal,
  'vat_amount': '0.00',
  'discount_amount': '0.00',
  'grand_total': grandTotal,
  'source': 'WALK_IN',
  'status': 'COMPLETED',
  'notes': '',
  'items': [
    {
      'id': 31,
      'transaction': 18,
      'variant_uom': 8,
      'variant_uom_code': 'PC',
      'qty': '2.00',
      'unit_price': '10.00',
      'subtotal': '20.00',
    },
  ],
  'payments': [
    {
      'id': 12,
      'transaction': 18,
      'method': 'CASH',
      'amount_tendered': '20.00',
      'reference_no': '',
      'timestamp': '2026-10-16T18:56:59.912001+08:00',
    },
  ],
  'receipt': {
    'id': 9,
    'transaction': 18,
    'or_number': 'OR-20261016-0007',
    'terminal_no': 'POS-01',
    'printed_at': '2026-10-16T18:56:59.912001+08:00',
  },
  'created_at': '2026-10-16T18:56:59.912001+08:00',
  'updated_at': '2026-10-16T18:56:59.912001+08:00',
};

Map<String, dynamic> _insufficient() => {
  'code': 'INSUFFICIENT_STOCK',
  'detail': 'Insufficient stock for Portland Cement — 40kg.',
  'shortfall': '1.00',
};

/// A path-aware fake adapter, because these tests need both a success and several
/// distinct failure bodies. Records every request so the payload can be asserted.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body, this.statusCode);

  final Map<String, dynamic> body;
  final int statusCode;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late _FakeAdapter adapter;
  late ApiClient client;
  late PosService service;
  late HttpClientAdapter originalAdapter;

  // `ApiClient.init()` assigns a `late final dio`, so it is NOT idempotent — once here,
  // not per test. Same harness note as the inventory and products service tests.
  setUpAll(() => client = ApiClient.instance..init());

  setUp(() {
    // Capture, do not null: `httpClientAdapter` is non-nullable, and leaving the
    // singleton swapped would leak this fake into every later test in the run.
    originalAdapter = client.dio.httpClientAdapter;
  });

  PosService serviceReturning(Map<String, dynamic> body, int statusCode) {
    adapter = _FakeAdapter(body, statusCode);
    client.dio.httpClientAdapter = adapter;
    return PosService(client: client);
  }

  tearDown(() => client.dio.httpClientAdapter = originalAdapter);

  Future<PosCheckoutResult> submit() => service.checkout(
    customerId: 2,
    items: const [PosCheckoutItem(variantUomId: 8, quantity: 2, unitPrice: 10)],
    payments: const [PosCheckoutPayment(method: 'CASH', amountTendered: 20)],
  );

  test('POSTs the payload the API expects, under the one data path', () async {
    service = serviceReturning(_transaction(), 201);
    await submit();

    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    expect(request.path, _transactionsPath);
    expect(request.method, 'POST');

    final sent = request.data as Map<String, dynamic>;
    expect(sent['customer'], 2);
    expect(sent['source'], 'WALK_IN');
    // `variant_id` is a VariantUOM id despite the name — the API resolves it as one
    // (Task 1). `cashier` must NOT be sent: it is read-only now, set server-side.
    expect(sent['items'], [
      {'variant_id': 8, 'qty': 2.0, 'unit_price': 10.0},
    ]);
    expect(sent['payments'], [
      {'method': 'CASH', 'amount_tendered': 20.0, 'reference_no': ''},
    ]);
    expect(
      sent.containsKey('cashier'),
      isFalse,
      reason: 'the actor is the server\'s to assign, never the client\'s',
    );
  });

  test('returns the finished transaction, so no second call is needed', () async {
    service = serviceReturning(_transaction(), 201);
    final result = await submit();

    expect(result.id, 18);
    expect(result.transactionNo, 'TRX-20261016-0007');
    expect(result.orNumber, 'OR-20261016-0007');
    expect(result.grandTotal, 20);
    expect(result.transDate.year, 2026);
    // The whole point of decision 06 section 1: the response carries the receipt.
    expect(adapter.requests, hasLength(1));
  });

  test('a short-stock 400 is distinguishable from a server failure', () async {
    service = serviceReturning(_insufficient(), 400);

    final error = await submit().then<Object?>((_) => null, onError: (e) => e);

    expect(error, isA<PosServiceException>());
    final failure = error! as PosServiceException;
    expect(failure.isInsufficientStock, isTrue);
    expect(failure.shortfall, 1);
    expect(failure.message, contains('Insufficient stock'));
  });

  test('a 500 is NOT reported as insufficient stock', () async {
    // If this ever passes as `isInsufficientStock`, the cart would tell a cashier to
    // reduce a quantity when the server was simply broken.
    service = serviceReturning({'detail': 'Internal server error'}, 500);

    final error = await submit().then<Object?>((_) => null, onError: (e) => e);

    expect(error, isA<PosServiceException>());
    expect((error! as PosServiceException).isInsufficientStock, isFalse);
  });

  test('a connection failure says so in words a cashier understands', () async {
    client.dio.httpClientAdapter = _ThrowingAdapter();
    service = PosService(client: client);

    final error = await submit().then<Object?>((_) => null, onError: (e) => e);

    expect(error, isA<PosServiceException>());
    expect(
      (error! as PosServiceException).message,
      'Cannot connect to the BuildPro server.',
    );
  });

  // Phase 1 Task 6 (audit remediation): the idempotent checkout contract.
  //
  // The server accepts an optional `Idempotency-Key` on POST /transactions/ and
  // POST /held-carts/{id}/complete/. Same key + same body answers 200 with the
  // ORIGINAL transaction instead of 201 with a new one, which is the only thing
  // that stops a retried timeout from ringing a second sale. So the client must
  // (a) send the header, and (b) parse a 200 replay exactly like a 201.
  group('idempotency', () {
    Future<PosCheckoutResult> submitWithKey(String? key) => service.checkout(
      customerId: 2,
      items: const [
        PosCheckoutItem(variantUomId: 8, quantity: 2, unitPrice: 10),
      ],
      payments: const [PosCheckoutPayment(method: 'CASH', amountTendered: 20)],
      idempotencyKey: key,
    );

    test('sends the Idempotency-Key header when given one', () async {
      service = serviceReturning(_transaction(), 201);
      await submitWithKey('0123456789abcdef0123456789abcdef');

      expect(
        adapter.requests.single.headers['Idempotency-Key'],
        '0123456789abcdef0123456789abcdef',
      );
    });

    test('omits the header when there is no key', () async {
      // The header is optional on the server, so an unkeyed checkout must keep
      // behaving exactly as it did before.
      service = serviceReturning(_transaction(), 201);
      await submitWithKey(null);

      expect(
        adapter.requests.single.headers.containsKey('Idempotency-Key'),
        isFalse,
      );
    });

    test('a 200 replay parses exactly like a 201', () async {
      service = serviceReturning(_transaction(), 200);
      final result = await submitWithKey('0123456789abcdef0123456789abcdef');

      expect(result.id, 18);
      expect(result.transactionNo, 'TRX-20261016-0007');
      expect(result.orNumber, 'OR-20261016-0007');
      expect(result.grandTotal, 20);
    });

    test('carries the SERVER line prices, not the client\'s', () async {
      // The server now ignores a client `unit_price` and prices each line from
      // VariantUOM.default_selling_price, so the response is the only truthful
      // source for what the receipt must print.
      service = serviceReturning(_transaction(), 201);
      final result = await submitWithKey(null);

      expect(result.lines, hasLength(1));
      expect(result.lines.single.variantUomId, 8);
      expect(result.lines.single.quantity, 2);
      expect(result.lines.single.unitPrice, 10);
      expect(result.lines.single.subtotal, 20);
    });
  });

  // Phase 1 Task 6: the new 400/409 codes must reach a cashier as words, not as
  // 'The sale could not be completed.'
  group('new sale error codes', () {
    Future<PosServiceException> failureFor(
      Map<String, dynamic> body,
      int status,
    ) async {
      service = serviceReturning(body, status);
      final error = await submit().then<Object?>(
        (_) => null,
        onError: (e) => e,
      );
      expect(error, isA<PosServiceException>());
      return error! as PosServiceException;
    }

    test('INVALID_SALE surfaces the server detail', () async {
      final failure = await failureFor({
        'code': 'INVALID_SALE',
        'detail': 'Item 1 has an invalid quantity.',
      }, 400);

      expect(failure.code, 'INVALID_SALE');
      expect(failure.message, 'Item 1 has an invalid quantity.');
      expect(failure.isInsufficientStock, isFalse);
    });

    test('CREDIT_LIMIT_EXCEEDED spells out the arithmetic', () async {
      final failure = await failureFor({
        'code': 'CREDIT_LIMIT_EXCEEDED',
        'detail': 'Credit limit exceeded.',
        'limit': '500.00',
        'outstanding': '400.00',
        'shortfall': '200.00',
      }, 400);

      expect(failure.code, 'CREDIT_LIMIT_EXCEEDED');
      expect(
        failure.message,
        'Credit limit exceeded: outstanding 400.00 + this sale 200.00 > '
        'limit 500.00.',
      );
      expect(failure.limit, 500);
      expect(failure.outstanding, 400);
      expect(failure.isInsufficientStock, isFalse);
    });

    test('IDEMPOTENCY_KEY_REUSED says the sale was NOT rung twice', () async {
      final failure = await failureFor({
        'code': 'IDEMPOTENCY_KEY_REUSED',
        'detail': 'Idempotency key already used with a different body.',
      }, 409);

      expect(failure.code, 'IDEMPOTENCY_KEY_REUSED');
      expect(failure.message, contains('different sale'));
    });
  });

  // Task 4 (decision 06 section 2): a walk-in sale CANNOT omit the customer.
  // SalesTransaction.customer is FK(PROTECT) with no null=True and the view reads
  // validated_data['customer'].id, so an anonymous sale still sends an id - the
  // Walk-in Customer that seed_demo creates. This resolves it once.
  group('resolving the Walk-in Customer', () {
    Map<String, dynamic> envelope(List<Map<String, dynamic>> results) => {
      'count': results.length,
      'next': null,
      'previous': null,
      'results': results,
    };

    test('finds the Walk-in Customer by name and returns its id', () async {
      final adapter = _FakeAdapter(
        envelope([
          {'id': 1, 'name': 'Juan Dela Cruz', 'customer_type': 'REGULAR'},
          {'id': 2, 'name': 'Walk-in Customer', 'customer_type': 'WALK_IN'},
        ]),
        200,
      );
      client.dio.httpClientAdapter = adapter;
      final service = PosService(client: client);

      expect(await service.fetchWalkInCustomerId(), 2);
      expect(adapter.requests.single.path, '/api/v1/customers/');
      expect(adapter.requests.single.method, 'GET');
    });

    test('fails loudly when the demo data has no Walk-in Customer', () async {
      // Better to refuse the sale than to send a wrong customer id and charge the
      // utang to somebody else.
      final adapter = _FakeAdapter(
        envelope([
          {'id': 1, 'name': 'Juan Dela Cruz', 'customer_type': 'REGULAR'},
        ]),
        200,
      );
      client.dio.httpClientAdapter = adapter;
      final service = PosService(client: client);

      final error = await service.fetchWalkInCustomerId().then<Object?>(
        (_) => null,
        onError: (e) => e,
      );
      expect(error, isA<PosServiceException>());
      expect((error! as PosServiceException).message, contains('Walk-in'));
    });
  });
}

/// Fails the way an unreachable server does.
class _ThrowingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException.connectionError(
      requestOptions: options,
      reason: 'refused',
    );
  }

  @override
  void close({bool force = false}) {}
}
