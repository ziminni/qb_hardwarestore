// Phase 5 F3 (decision 18): what the till SENDS for a delivery.
//
// The wire is an optional `delivery` object — `{address, contact_name,
// contact_phone, scheduled_date: "YYYY-MM-DD", fee}` — on `POST
// /transactions/` and on `POST /held-carts/{id}/complete/`. A malformed body is
// refused with INVALID_DELIVERY and writes no sale, no stock and no slip, so the
// shape is pinned here rather than trusted.

import 'dart:convert';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/delivery.dart';
import 'package:client/data/models/sale_discount.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/held_cart_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

const _heldCartsPath = '/api/v1/held-carts/';

final _draft = DeliveryDraft(
  address: '12 Mabini St, Cebu City',
  contactName: 'Maria Santos',
  contactPhone: '09171234567',
  scheduledDate: DateTime(2026, 11, 12),
  fee: 50,
);

final _wireDelivery = <String, dynamic>{
  'address': '12 Mabini St, Cebu City',
  'contact_name': 'Maria Santos',
  'contact_phone': '09171234567',
  'scheduled_date': '2026-11-12',
  'fee': '50.00',
};

Map<String, dynamic> _transaction({String deliveryFee = '0.00'}) => {
  'id': 18,
  'customer': 2,
  'customer_name': 'Walk-in Customer',
  'cashier': 1,
  'cashier_name': 'Ada Ministrator',
  'transaction_no': 'TRX-20261112-0007',
  'trans_date': '2026-11-12T10:00:00+08:00',
  'vatable_sales': '848.21',
  'vat_amount': '101.79',
  'discount_amount': '0.00',
  'delivery_fee': deliveryFee,
  'grand_total': '950.00',
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
      'unit_price': '450.00',
      'subtotal': '900.00',
    },
  ],
  'payments': [
    {
      'id': 12,
      'transaction': 18,
      'method': 'CASH',
      'amount_tendered': '1000.00',
      'reference_no': '',
      'timestamp': '2026-11-12T10:00:00+08:00',
    },
  ],
  'receipt': {
    'id': 9,
    'transaction': 18,
    'or_number': 'OR-20261112-0007',
    'terminal_no': 'POS-01',
    'printed_at': '2026-11-12T10:00:00+08:00',
  },
  'created_at': '2026-11-12T10:00:00+08:00',
  'updated_at': '2026-11-12T10:00:00+08:00',
};

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.body);

  final Map<String, dynamic> body;
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
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// Records what the viewmodel hands the repository, so the cart-to-checkout
/// hand-off has its own proof without a server.
class _RecordingPosRepository extends PosRepository {
  _RecordingPosRepository() : super(PosService());

  DeliveryDraft? lastDelivery;

  @override
  Future<int> walkInCustomerId() async => 1;

  @override
  Future<PosCheckoutResult> checkout({
    required int customerId,
    required List<PosCheckoutItem> items,
    required List<PosCheckoutPayment> payments,
    String source = 'WALK_IN',
    String? idempotencyKey,
    PosDiscount? discount,
    String? discountApproval,
    DeliveryDraft? delivery,
  }) async {
    lastDelivery = delivery;
    return PosCheckoutResult(
      id: 7,
      transactionNo: 'TRX-20261112-0007',
      orNumber: 'OR-20261112-0007',
      transDate: DateTime(2026, 11, 12, 10),
      grandTotal: 950,
      deliveryFee: delivery?.fee ?? 0,
    );
  }
}

void main() {
  late _FakeAdapter adapter;
  late ApiClient client;
  late HttpClientAdapter originalAdapter;

  setUpAll(() => client = ApiClient.instance..init());

  setUp(() => originalAdapter = client.dio.httpClientAdapter);
  tearDown(() => client.dio.httpClientAdapter = originalAdapter);

  PosService posService() {
    adapter = _FakeAdapter(_transaction(deliveryFee: '50.00'));
    client.dio.httpClientAdapter = adapter;
    return PosService(client: client);
  }

  Future<PosCheckoutResult> checkout(
    PosService service, {
    DeliveryDraft? delivery,
  }) => service.checkout(
    customerId: 2,
    items: const [
      PosCheckoutItem(variantUomId: 8, quantity: 2, unitPrice: 450),
    ],
    payments: const [PosCheckoutPayment(method: 'CASH', amountTendered: 1000)],
    delivery: delivery,
  );

  test(
    'checkout carries the delivery object exactly as the server expects it',
    () async {
      await checkout(posService(), delivery: _draft);

      final sent = adapter.requests.single.data as Map<String, dynamic>;
      expect(sent['delivery'], _wireDelivery);
    },
  );

  test('a carried-out sale sends NO delivery key at all', () async {
    await checkout(posService());

    final sent = adapter.requests.single.data as Map<String, dynamic>;
    expect(
      sent.containsKey('delivery'),
      isFalse,
      reason: 'an empty object would be INVALID_DELIVERY on the server',
    );
  });

  test('the server\'s delivery_fee reaches the receipt', () async {
    final result = await checkout(posService(), delivery: _draft);
    expect(result.deliveryFee, 50);
  });

  test(
    'a pre-B3 body has no delivery_fee and the receipt shows no charge',
    () async {
      adapter = _FakeAdapter(_transaction()..remove('delivery_fee'));
      client.dio.httpClientAdapter = adapter;
      final result = await checkout(PosService(client: client));
      expect(result.deliveryFee, 0);
    },
  );

  test('completing a held cart sends the same delivery object', () async {
    adapter = _FakeAdapter(_transaction(deliveryFee: '50.00'));
    client.dio.httpClientAdapter = adapter;

    await HeldCartService(client: client).complete(
      5,
      payments: const [
        PosCheckoutPayment(method: 'CASH', amountTendered: 1000),
      ],
      delivery: _draft,
    );

    final request = adapter.requests.single;
    expect(request.path, '${_heldCartsPath}5/complete/');
    expect(request.method, 'POST');
    expect((request.data as Map<String, dynamic>)['delivery'], _wireDelivery);
  });

  test('a held cart completed with no delivery sends no key', () async {
    adapter = _FakeAdapter(_transaction());
    client.dio.httpClientAdapter = adapter;

    await HeldCartService(client: client).complete(
      5,
      payments: const [
        PosCheckoutPayment(method: 'CASH', amountTendered: 1000),
      ],
    );

    final sent = adapter.requests.single.data as Map<String, dynamic>;
    expect(sent.containsKey('delivery'), isFalse);
  });

  test('the till viewmodel passes the delivery to the checkout call', () async {
    final repository = _RecordingPosRepository();
    final inventory = seededInventory();
    final cart = PosTransactionViewmodel(inventory, pos: repository);
    final product = cart.filteredProducts.first;
    expect(cart.addLine(cart.saleOptionsFor(product).first, 2), isNull);

    await cart.submit(delivery: _draft);

    expect(repository.lastDelivery?.toJson(), _wireDelivery);
    expect(
      cart.receipts.single.deliveryFee,
      50,
      reason: 'the receipt prints the server\'s charge, not the cart\'s',
    );
  });

  test('the wire fee is 2 dp text, never a double', () {
    expect(_draft.toJson()['fee'], '50.00');
  });
}
