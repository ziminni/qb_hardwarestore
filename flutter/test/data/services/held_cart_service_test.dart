// Phase 1 Task 6 (audit remediation): `POST /api/v1/held-carts/{id}/complete/`
// honours `Idempotency-Key`.
//
// This is the ONE call where the key matters most. `complete` runs `process_sale`
// and then DELETES the cart, so a retry after a timeout has nothing left to
// resolve by id — the server answers 200 with the original sale when the key
// matches, and 404 without it. The client therefore must send the key, and must
// read a 200 replay exactly like the 201 of a first-time completion.

import 'dart:convert';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/services/held_cart_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

const _completePath = '/api/v1/held-carts/7/complete/';

Map<String, dynamic> _sale() => {
  'id': 18,
  'transaction_no': 'TRX-20261016-0007',
  'trans_date': '2026-10-16T18:56:59.912001+08:00',
  'grand_total': '20.00',
  'items': [],
  'payments': [],
  'receipt': {'or_number': 'OR-20261016-0007'},
};

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
  late ApiClient client;
  late _FakeAdapter adapter;
  late HttpClientAdapter originalAdapter;

  setUpAll(() => client = ApiClient.instance..init());

  setUp(() => originalAdapter = client.dio.httpClientAdapter);

  tearDown(() => client.dio.httpClientAdapter = originalAdapter);

  HeldCartService serviceReturning(int statusCode) {
    adapter = _FakeAdapter(_sale(), statusCode);
    client.dio.httpClientAdapter = adapter;
    return HeldCartService(client: client);
  }

  Future<Map<String, dynamic>> complete(HeldCartService service, String? key) =>
      service.complete(
        7,
        payments: const [
          PosCheckoutPayment(method: 'CASH', amountTendered: 20),
        ],
        idempotencyKey: key,
      );

  test('sends the Idempotency-Key header when given one', () async {
    final service = serviceReturning(201);

    await complete(service, '0123456789abcdef0123456789abcdef');

    final request = adapter.requests.single;
    expect(request.path, _completePath);
    expect(request.method, 'POST');
    expect(
      request.headers['Idempotency-Key'],
      '0123456789abcdef0123456789abcdef',
    );
  });

  test('omits the header when there is no key', () async {
    final service = serviceReturning(201);

    await complete(service, null);

    expect(
      adapter.requests.single.headers.containsKey('Idempotency-Key'),
      isFalse,
    );
  });

  test('a 200 replay of an already-completed cart returns the same sale',
      () async {
    // The cart is gone by then, so anything but a parse here would surface as a
    // "held carts could not be loaded" failure for a sale that DID happen.
    final service = serviceReturning(200);

    final sale = await complete(service, '0123456789abcdef0123456789abcdef');

    expect(sale['id'], 18);
    expect(sale['transaction_no'], 'TRX-20261016-0007');
  });
}
