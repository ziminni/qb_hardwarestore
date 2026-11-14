import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/services/inventory_service.dart';
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
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// One line as Phase 5 B1 serialises it: the selling unit and its read-only
/// copies ride along with the counts, which are all in that unit.
Map<String, dynamic> _unitLine() => {
  'id': 11,
  'po': 1,
  'variant': 8,
  'variant_name': 'Portland 40kg',
  'variant_uom': 11,
  'uom_code': 'BAG',
  'conversion_factor': '25.00',
  'uom_is_whole': true,
  'ordered_qty': '10.00',
  'unit_cost': '250.00',
  'received_qty': '2.00',
};

Map<String, dynamic> _po({int id = 1}) => {
  'id': id,
  'supplier': 2,
  'created_by': 3,
  'created_by_name': 'Stock Manager',
  'order_date': '2026-10-19',
  'expected_delivery': null,
  'status': 'DRAFT',
  'notes': '',
  'items': [
    {
      'id': 11,
      'po': id,
      'variant': 8,
      'variant_name': 'Portland 40kg',
      'ordered_qty': '10.00',
      'unit_cost': '50.00',
      'received_qty': '0.00',
    },
  ],
  'created_at': '2026-10-19T08:00:00Z',
  'updated_at': '2026-10-19T08:00:00Z',
};

void main() {
  late _FakeAdapter adapter;
  late InventoryService service;
  RequestOptions? lastRequest;

  setUpAll(() {
    ApiClient.instance.init();
  });

  setUp(() {
    lastRequest = null;
    adapter = _FakeAdapter((options) {
      lastRequest = options;
      return _json({});
    });
    ApiClient.instance.dio.httpClientAdapter = adapter;
    service = InventoryService();
  });

  test('purchase orders parse with nested items', () async {
    adapter.respond = (options) {
      lastRequest = options;
      return _json({
        'count': 1,
        'next': null,
        'previous': null,
        'results': [_po()],
      });
    };

    final orders = await service.fetchPurchaseOrders();

    expect(orders, hasLength(1));
    expect(orders.single.items.single.receivedQty, 0.0);
    expect(lastRequest?.path, '/api/v1/purchase-orders/');
  });

  test('recording a receipt posts the po and received quantities', () async {
    adapter.respond = (options) {
      lastRequest = options;
      return _json({
        'id': 5,
        'po': 1,
        'received_by': 3,
        'received_by_name': 'Stock Manager',
        'receive_date': '2026-10-19',
        'delivery_receipt_no': 'DR-1',
        'notes': '',
        'batches': [],
        'created_at': '2026-10-19T08:00:00Z',
      }, status: 201);
    };

    final receipt = await service.createReceipt(
      poId: 1,
      items: const [ReceiptLine(poItemId: 11, qty: 4)],
      deliveryReceiptNo: 'DR-1',
    );

    expect(receipt.id, 5);
    expect(lastRequest?.path, '/api/v1/goods-receipts/');
    expect(lastRequest?.data, {
      'po': 1,
      'delivery_receipt_no': 'DR-1',
      'items': [
        {'po_item': 11, 'qty': 4.0},
      ],
    });
  });

  // Phase 5 F1 (decision 18): the wire grew a unit; a line from a server that
  // predates it must keep its base-unit meaning instead of a guessed one.
  test('a PO line parses its unit, factor and whole flag', () async {
    adapter.respond = (options) => _json({
      'count': 1,
      'next': null,
      'previous': null,
      'results': [
        {
          ..._po(),
          'items': [_unitLine()],
        },
      ],
    });

    final item = (await service.fetchPurchaseOrders()).single.items.single;

    expect(item.variantUomId, 11);
    expect(item.unitCode, 'BAG');
    expect(item.conversionFactor, 25);
    expect(item.unitIsWhole, isTrue);
    expect(item.orderedQty, 10);
    // The line's own numbers stay in BAG: 250 is the base equivalent, never the
    // value the wire carried.
    expect(item.orderedBaseQty, 250);
  });

  test('an older server line keeps factor 1 and names no unit', () async {
    adapter.respond = (options) => _json({
      'count': 1,
      'next': null,
      'previous': null,
      'results': [_po()],
    });

    final item = (await service.fetchPurchaseOrders()).single.items.single;

    expect(item.variantUomId, isNull);
    expect(item.unitCode, '');
    expect(item.conversionFactor, 1);
    expect(item.unitIsWhole, isFalse);
    expect(item.orderedBaseQty, item.orderedQty);
  });

  test(
    'a receipt sends the counted quantity, never the base equivalent',
    () async {
      adapter.respond = (options) {
        lastRequest = options;
        return _json({
          'id': 5,
          'po': 1,
          'received_by': 3,
          'received_by_name': 'Stock Manager',
          'receive_date': '2026-10-19',
          'delivery_receipt_no': 'DR-1',
          'notes': '',
          'batches': [],
          'created_at': '2026-10-19T08:00:00Z',
        }, status: 201);
      };

      // 2 BAG of a 25 KG bag is 50 KG of stock, and the server does that
      // multiplication: the payload keeps the 2 the receiver counted.
      await service.createReceipt(
        poId: 1,
        items: const [ReceiptLine(poItemId: 11, qty: 2)],
        deliveryReceiptNo: 'DR-1',
      );

      expect(lastRequest?.data, {
        'po': 1,
        'delivery_receipt_no': 'DR-1',
        'items': [
          {'po_item': 11, 'qty': 2.0},
        ],
      });
    },
  );

  test('a refused receipt surfaces the server detail sentence', () async {
    const detail =
        '0.015 BAG cannot become whole hundredths of base stock: record a '
        'quantity that yields whole hundredths of the base unit.';
    adapter.respond = (options) => _json({
      'code': 'RECEIPT_QUANTITY_UNREPRESENTABLE',
      'detail': detail,
    }, status: 400);

    await expectLater(
      service.createReceipt(
        poId: 1,
        items: const [ReceiptLine(poItemId: 11, qty: 0.015)],
      ),
      throwsA(
        isA<InventoryServiceException>().having(
          (error) => error.message,
          'message',
          detail,
        ),
      ),
    );
  });

  test('processing a receipt returns the minted batches', () async {
    adapter.respond = (options) {
      lastRequest = options;
      return _json([
        {
          'id': 21,
          'variant': 8,
          'receipt': 5,
          'initial_qty': '4.00',
          'current_qty': '4.00',
          'unit_cost_landed': '50.00',
          'markup_percentage': '0.00',
          'batch_selling_price': '50.00',
          'expiration_date': null,
          'created_at': '2026-10-19T08:00:00Z',
        },
      ]);
    };

    final batches = await service.processReceipt(5);

    expect(batches, hasLength(1));
    expect(batches.single.currentQty, 4.0);
    expect(lastRequest?.path, '/api/v1/goods-receipts/5/process/');
  });
}
