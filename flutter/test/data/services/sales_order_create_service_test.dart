// Phase 5 F3 follow-up: creating a sales order (owner-authorised create-only
// entry). The contract these tests pin is `POST /api/v1/sales-orders/`
// (apps/pos/serializers.py::SalesOrderSerializer):
//
//   {customer, notes?, items: [{variant_uom, qty, unit_price}], delivery?}
//
// `status` must NOT be sent — the server defaults CONFIRMED and a client that set
// it would be writing a state the order never went through. A refusal must reach
// the screen as the server's own sentence (or its documented code), and a body
// without an order must never be reported as a success.

import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/delivery.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  ResponseBody Function(RequestOptions options) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object? body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// The created order, shaped like the real serializer's response: `delivery` is
/// write-only, so it is absent here exactly as it is on the wire.
Map<String, dynamic> _createdOrder() => {
  'id': 12,
  'order_no': 'SO-20261112-0001',
  'customer': 3,
  'quotation': null,
  'status': 'CONFIRMED',
  'notes': 'Deliver after 3pm',
  'items': [
    {
      'id': 41,
      'order': 12,
      'variant_uom': 7,
      'qty': '2.00',
      'unit_price': '250.00',
    },
  ],
  'created_at': '2026-11-12T08:00:00Z',
  'updated_at': '2026-11-12T08:00:00Z',
};

SalesOrderDraft _draft({bool deliver = false}) => SalesOrderDraft(
  customerId: 3,
  notes: 'Deliver after 3pm',
  lines: const [SalesOrderLineDraft(variantUomId: 7, qty: 2, unitPrice: 250)],
  delivery: deliver
      ? DeliveryDraft(
          address: '12 Mabini St, Cebu',
          contactName: 'Ana Reyes',
          contactPhone: '0917 555 1234',
          scheduledDate: DateTime(2026, 11, 14),
          fee: 150,
        )
      : null,
);

void main() {
  late _FakeAdapter adapter;
  late SalesService service;
  HttpClientAdapter? original;

  setUpAll(() => ApiClient.instance.init());

  setUp(() {
    original = ApiClient.instance.dio.httpClientAdapter;
    adapter = _FakeAdapter((_) => _json(_createdOrder(), status: 201));
    ApiClient.instance.dio.httpClientAdapter = adapter;
    service = SalesService();
  });

  tearDown(() => ApiClient.instance.dio.httpClientAdapter = original!);

  test('POSTs customer, notes and lines, and never a status', () async {
    await service.createSalesOrder(_draft());

    expect(adapter.requests, hasLength(1));
    final request = adapter.requests.single;
    expect(request.path, '/api/v1/sales-orders/');
    expect(request.method, 'POST');

    final sent = request.data as Map<String, dynamic>;
    expect(sent['customer'], 3);
    expect(sent['notes'], 'Deliver after 3pm');
    expect(sent['items'], [
      {'variant_uom': 7, 'qty': 2.0, 'unit_price': '250.00'},
    ]);
    expect(
      sent.containsKey('status'),
      isFalse,
      reason: 'CONFIRMED is the server default; the client invents no state',
    );
    expect(
      sent.containsKey('delivery'),
      isFalse,
      reason: 'a pickup order carries no delivery object at all',
    );
  });

  test('a Deliver order sends the delivery object, fee at 2 dp', () async {
    await service.createSalesOrder(_draft(deliver: true));

    final sent = adapter.requests.single.data as Map<String, dynamic>;
    expect(sent['delivery'], {
      'address': '12 Mabini St, Cebu',
      'contact_name': 'Ana Reyes',
      'contact_phone': '0917 555 1234',
      'scheduled_date': '2026-11-14',
      'fee': '150.00',
    });
  });

  test('returns the server row: number, status and lines as stored', () async {
    final order = await service.createSalesOrder(_draft());

    expect(order.id, 12);
    expect(order.number, 'SO-20261112-0001');
    expect(order.status, 'CONFIRMED');
    expect(order.items.single.qty, 2);
    expect(order.items.single.unitPrice, 250);
  });

  test('a WHOLE_UNIT_QUANTITY 400 shows the server sentence', () async {
    adapter.respond = (_) => _json({
      'code': 'WHOLE_UNIT_QUANTITY',
      'detail': 'Cement 40kg, PC: a whole unit takes a whole number of units.',
    }, status: 400);

    final error = await service
        .createSalesOrder(_draft())
        .then<Object?>((_) => null, onError: (e) => e);

    expect(error, isA<SalesServiceException>());
    expect(
      (error! as SalesServiceException).message,
      'Cement 40kg, PC: a whole unit takes a whole number of units.',
    );
  });

  test(
    'an INVALID_DELIVERY code with no prose still says what to fix',
    () async {
      adapter.respond = (_) => _json({'code': 'INVALID_DELIVERY'}, status: 400);

      final error = await service
          .createSalesOrder(_draft(deliver: true))
          .then<Object?>((_) => null, onError: (e) => e);

      expect(error, isA<SalesServiceException>());
      expect((error! as SalesServiceException).message, contains('delivery'));
    },
  );

  test('a 403 says the role cannot create an order', () async {
    adapter.respond = (_) =>
        _json({'detail': 'You do not have permission.'}, status: 403);

    final error = await service
        .createSalesOrder(_draft())
        .then<Object?>((_) => null, onError: (e) => e);

    expect(error, isA<SalesServiceException>());
    expect(
      (error! as SalesServiceException).message.toLowerCase(),
      contains('permission'),
    );
  });

  test('a body with no order is a failure, never a silent success', () async {
    adapter.respond = (_) => _json(null, status: 201);

    final error = await service
        .createSalesOrder(_draft())
        .then<Object?>((_) => null, onError: (e) => e);

    expect(error, isA<SalesServiceException>());
  });
}
