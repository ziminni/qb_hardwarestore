// Owner rulings (utang markup, drawer carry) — the WIRE, not the widget tree.
//
// Every test here pins a number the server prices or records, so a client that
// "helpfully" re-derives it (rounding a credit price, inventing a 0.00 float,
// assuming the whole count stays in the drawer) fails loudly instead of taking
// money the shop never asked for.

import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/pos_transaction.dart' hide PosCheckoutResult;
import 'package:client/data/models/product_writes.dart';
import 'package:client/data/models/store_settings.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/services/held_cart_service.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/pos/widgets/receipt_document.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;

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

Map<String, dynamic> _shiftJson({Object? cashLeft = _absent}) => {
  'id': 4,
  'cashier_name': 'Ada',
  'status': 'CLOSED',
  'opening_float': '100.00',
  'closing_count': '250.00',
  if (cashLeft != _absent) 'cash_left_in_drawer': cashLeft,
  'opened_at': '2026-01-01T08:00:00+08:00',
  'closed_at': '2026-01-01T18:00:00+08:00',
  'notes': '',
  'z_reading': {
    'transaction_count': 3,
    'gross_sales': '150.00',
    'cash_sales': '150.00',
    'card_sales': '0.00',
    'gcash_sales': '0.00',
    'expected_drawer': '250.00',
    'variance': '0.00',
    'cash_taken_out': '250.00',
    'opening_difference': '-20.00',
  },
};

const _absent = Object();

void main() {
  // `ApiClient.init()` is NOT idempotent (`late final dio`), so it runs once and
  // each test only swaps the adapter - the same pattern shift_service_test uses.
  late ApiClient client;
  HttpClientAdapter? replaced;

  setUpAll(() {
    client = ApiClient.instance..init();
  });

  setUp(() {
    replaced = client.dio.httpClientAdapter;
  });

  tearDown(() {
    if (replaced != null) client.dio.httpClientAdapter = replaced!;
    replaced = null;
  });

  void serve(HttpClientAdapter adapter) {
    client.dio.httpClientAdapter = adapter;
  }

  group('drawer carry (shift close / opening suggestion)', () {
    test('close sends cash_left when the cashier said what stays', () async {
      late Map<String, dynamic> sent;
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = _FakeAdapter((options) {
        sent = options.data as Map<String, dynamic>;
        return _json(_shiftJson(cashLeft: '50.00'));
      });
      serve(dio.httpClientAdapter);
      final service = ShiftService(client: client);

      final closed = await service.closeShift(4, 250, cashLeft: 50);

      // The wire carries BOTH numbers: the count and what stays behind.
      expect(sent['closing_count'], '250.00');
      expect(sent['cash_left'], '50.00');
      expect(closed.cashLeftInDrawer, 50);
      expect(closed.zReading!.cashTakenOut, 250);
      expect(closed.zReading!.openingDifference, -20);
    });

    test('close omits cash_left when the question was not asked', () async {
      late Map<String, dynamic> sent;
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = _FakeAdapter((options) {
        sent = options.data as Map<String, dynamic>;
        return _json(_shiftJson(cashLeft: null));
      });
      serve(dio.httpClientAdapter);
      final service = ShiftService(client: client);

      final closed = await service.closeShift(4, 250);

      // Omitted, not assumed: "not recorded" must stay different from 0.00.
      expect(sent.containsKey('cash_left'), isFalse);
      expect(closed.cashLeftInDrawer, isNull);
    });

    test('opening suggestion keeps null and 0.00 apart', () async {
      final responses = <Object>[
        {
          'suggested_float': null,
          'source': null,
          'cleared': false,
        },
        {
          'suggested_float': '0.00',
          'source': {
            'shift_id': 9,
            'cashier_name': 'Ada',
            'closed_at': '2026-01-01T18:00:00+08:00',
            'closing_count': '250.00',
            'cash_left_in_drawer': '0.00',
          },
          'cleared': true,
        },
      ];
      var index = 0;
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = _FakeAdapter(
        (options) => _json(responses[index++]),
      );
      serve(dio.httpClientAdapter);
      final service = ShiftService(client: client);

      final none = await service.fetchOpeningSuggestion();
      expect(none.suggestedFloat, isNull);
      expect(none.cleared, isFalse);
      expect(none.source, isNull);

      final cleared = await service.fetchOpeningSuggestion();
      expect(cleared.suggestedFloat, 0);
      expect(cleared.cleared, isTrue);
      expect(cleared.source!.cashLeftInDrawer, 0);
    });

    test('an unreachable suggestion throws instead of inventing 0.00', () async {
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = _FakeAdapter(
        (options) => _json({'detail': 'Server error'}, status: 500),
      );
      serve(dio.httpClientAdapter);
      final service = ShiftService(client: client);

      await expectLater(
        service.fetchOpeningSuggestion(),
        throwsA(isA<ShiftServiceException>()),
      );
    });
  });

  group('utang markup', () {
    test('a variant unit reads the server credit price, never re-derives it',
        () {
      final unit = VariantUom.fromJson({
        'id': 8,
        'variant': 2,
        'uom': 1,
        'uom_code': 'PC',
        'uom_name': 'Piece',
        'barcode_qr': 'QB000008-4',
        'conversion_factor': '1.00',
        'default_selling_price': '10.00',
        'credit_markup_kind': 'PERCENT',
        'credit_markup_value': '5.00',
        'credit_selling_price': '10.50',
      });
      expect(unit.defaultSellingPrice, 10);
      expect(unit.creditSellingPrice, 10.5);
      expect(unit.hasCreditMarkup, isTrue);

      // A body from before the field: cash price IS the credit price.
      final legacy = VariantUom.fromJson({
        'id': 9,
        'variant': 2,
        'uom': 1,
        'uom_code': 'PC',
        'uom_name': 'Piece',
        'barcode_qr': 'QB000009-0',
        'conversion_factor': '1.00',
        'default_selling_price': '10.00',
      });
      expect(legacy.creditSellingPrice, 10);
      expect(legacy.creditMarkupKind, 'NONE');
      expect(legacy.hasCreditMarkup, isFalse);
    });

    test('the cart previews credit prices while cash totals stay agreed', () {
      const line = PosCartLine(
        variantUomId: 8,
        productName: 'Wire',
        variantName: 'Standard',
        quantity: 2,
        unit: 'PC',
        unitPrice: 10,
        availableQuantity: 10,
        creditUnitPrice: 10.5,
      );
      expect(line.total, 20, reason: 'cash price is unchanged');
      expect(line.creditTotal, 21, reason: 'credit price covers every unit');
    });

    test('checkout sends credit_sale on the wire, both ways', () async {
      final sent = <Map<String, dynamic>>[];
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = _FakeAdapter((options) {
        sent.add(options.data as Map<String, dynamic>);
        return _json({
          'id': 18,
          'transaction_no': 'TRX-1',
          'trans_date': '2026-01-01T09:00:00+08:00',
          'grand_total': '20.00',
          'receipt': {'or_number': 'OR-1'},
        });
      });
      serve(dio.httpClientAdapter);
      final service = PosService(client: client);

      await service.checkout(
        customerId: 1,
        items: const [PosCheckoutItem(variantUomId: 8, quantity: 1, unitPrice: 10)],
        payments: const [
          PosCheckoutPayment(method: 'CASH', amountTendered: 10),
        ],
        creditSale: true,
      );
      await service.checkout(
        customerId: 1,
        items: const [PosCheckoutItem(variantUomId: 8, quantity: 1, unitPrice: 10)],
        payments: const [
          PosCheckoutPayment(method: 'CASH', amountTendered: 10),
        ],
      );

      expect(sent.first['credit_sale'], isTrue);
      expect(sent.last['credit_sale'], isFalse);
    });

    test('held-cart complete carries the same flag', () async {
      late Map<String, dynamic> sent;
      final dio = Dio(BaseOptions(baseUrl: 'http://test'));
      dio.httpClientAdapter = _FakeAdapter((options) {
        sent = options.data as Map<String, dynamic>;
        return _json({
          'id': 19,
          'transaction_no': 'TRX-2',
          'trans_date': '2026-01-01T09:00:00+08:00',
          'grand_total': '10.50',
          'receipt': {'or_number': 'OR-2'},
        });
      });
      serve(dio.httpClientAdapter);
      final service = HeldCartService(client: client);

      await service.complete(
        3,
        payments: const [
          PosCheckoutPayment(method: 'CASH', amountTendered: 10.5),
        ],
        creditSale: true,
      );

      expect(sent['credit_sale'], isTrue);
    });

    test('product writes carry the markup without ever making it mandatory',
        () {
      const create = NewProductDraft(
        categoryId: 1,
        brandId: 1,
        baseName: 'Wire',
        description: '',
        imageUrl: '',
        variantName: 'Standard',
        baseUomId: 1,
        minStockThreshold: 0,
        maxStockLevel: 0,
        sellingPrice: 10,
        creditMarkupKind: 'PERCENT',
        creditMarkupValue: 5,
      );
      final body = create.sellingUnitBody(2, 1);
      expect(body['credit_markup_kind'], 'PERCENT');
      expect(body['credit_markup_value'], 5);

      // An edit that does not touch the markup sends NEITHER key, so a stored
      // markup survives a price change.
      const untouched = ProductEditDraft(
        productId: 1,
        variantId: 2,
        sellingUnitId: 8,
        sellingPrice: 12,
      );
      expect(untouched.sellingUnitBody.containsKey('credit_markup_kind'), isFalse);
      expect(
        untouched.sellingUnitBody.containsKey('credit_markup_value'),
        isFalse,
      );

      const cleared = ProductEditDraft(
        productId: 1,
        variantId: 2,
        sellingUnitId: 8,
        creditMarkupKind: 'NONE',
        creditMarkupValue: 0,
      );
      expect(cleared.sellingUnitBody['credit_markup_kind'], 'NONE');
      expect(cleared.sellingUnitBody['credit_markup_value'], 0);
    });
  });

  group('tender fees (settings preview & server receipt)', () {
    test('store settings round-trip tender_fees and preview without sending fees on checkout', () {
      final settings = StoreSettings.fromJson({
        'vat_registered': true,
        'vat_rate': '12.00',
        'discount_cap_percent': '10.00',
        'tender_fees': [
          {
            'method': 'GCASH',
            'kind': 'PERCENT',
            'value': '2.00',
            'is_active': true,
          },
          {
            'method': 'CARD',
            'kind': 'AMOUNT',
            'value': '15.00',
            'is_active': false,
          },
        ],
      });

      expect(settings.previewFee('GCASH', 500), 10.00);
      expect(settings.previewFee('CARD', 500), 0.00);
      expect(settings.previewFee('CASH', 500), 0.00);

      final patch = settings.toPatchJson();
      final fees = patch['tender_fees'] as List<dynamic>;
      expect(fees.first, {
        'method': 'GCASH',
        'kind': 'PERCENT',
        'value': '2.00',
        'is_active': true,
      });
    });

    test('receipt prints server-stored payment_fee separate from VAT', () {
      final result = PosCheckoutResult.fromJson({
        'id': 44,
        'transaction_no': 'TRX-44',
        'trans_date': '2026-01-01T10:00:00+08:00',
        'grand_total': '510.00',
        'payment_fee': '10.00',
        'vatable_sales': '446.43',
        'vat_amount': '53.57',
        'vat_registered': true,
        'receipt': {'or_number': 'OR-44'},
        'payments': [
          {
            'method': 'GCASH',
            'amount_tendered': '510.00',
            'fee': '10.00',
            'status': 'CLEARED',
          },
        ],
      });

      expect(result.paymentFee, 10.00);
      expect(result.payments.single.fee, 10.00);

      final content = ReceiptContent(
        PosReceipt(
          reference: result.transactionNo,
          officialReceiptNumber: result.orNumber,
          createdAt: result.transDate,
          lines: const [],
          paymentMethod: 'GCASH',
          amountPaid: 510,
          total: result.grandTotal,
          paymentFee: result.paymentFee,
          payments: result.payments,
          vatableSales: result.vatableSales,
          vatAmount: result.vatAmount,
          vatRegistered: true,
          vatRate: 12,
        ),
      );
      final labels = [for (final row in content.amounts) row.label];
      expect(labels, contains('Payment fee'));
    });
  });
}
