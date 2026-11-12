// Phase 5 F4 (decision 18): the stored-at fields the client reads.
//
// The wire contract (B4, ENDPOINTS.md §3.3) is `stored_at` (id) plus
// `stored_at_name` (label) on products, variants, selling units and sale items.
// Every one of them is READ-ONLY: a product is stored somewhere, and its
// variants, units and lines inherit that label.
//
// The point of these tests is the LEGACY body: a response written before B4 has
// neither field. That is a real state (the server keeps old rows) and must read
// as "no location known" — never as location 0, never as an invented "Store".

import 'package:client/data/models/delivery.dart';
// `PosCheckoutResult` also exists in the services layer (the sale REQUEST
// result). This test reads the sale RESPONSE, so the model is hidden.
import 'package:client/data/models/pos_transaction.dart' hide PosCheckoutResult;
import 'package:client/data/models/product.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _productJson({
  bool withStoredAt = true,
  Object? storedAtId = 2,
  Object? storedAtName = 'Bodega',
}) => {
  'id': 7,
  'category': 1,
  'category_name': 'Cement',
  'brand': 1,
  'brand_name': 'Holcim',
  'base_name': 'Portland Cement',
  'description': '',
  'image_url': '',
  'is_active': true,
  if (withStoredAt) ...{
    'stored_at': storedAtId,
    'stored_at_name': storedAtName,
  },
  'variants': [
    {
      'id': 9,
      'product': 7,
      'variant_name': '40 kg',
      'base_uom': 2,
      'base_uom_code': 'BAG',
      'min_stock_threshold': '5.00',
      'max_stock_level': '0.00',
      'is_active': true,
      if (withStoredAt) ...{
        'stored_at': storedAtId,
        'stored_at_name': storedAtName,
      },
      'selling_uoms': [
        {
          'id': 11,
          'variant': 9,
          'uom': 2,
          'uom_code': 'BAG',
          'uom_name': 'Bag',
          'barcode_qr': 'QB000009-0',
          'conversion_factor': '1.00',
          'default_selling_price': '270.00',
          'uom_is_whole': true,
          if (withStoredAt) ...{
            'stored_at': storedAtId,
            'stored_at_name': storedAtName,
          },
        },
      ],
    },
  ],
};

void main() {
  group('StorageLocation', () {
    test('decodes the API row', () {
      final location = StorageLocation.fromJson({
        'id': 2,
        'name': 'Bodega',
        'is_active': true,
      });

      expect(location.id, 2);
      expect(location.name, 'Bodega');
      expect(location.isActive, isTrue);
    });

    test('a row with no is_active reads as active, not as hidden', () {
      // A serializer that omitted the flag would otherwise hide every place.
      final location = StorageLocation.fromJson({'id': 1, 'name': 'Store'});
      expect(location.isActive, isTrue);
    });
  });

  group('product rows carry the pick-up point', () {
    test('product, variant and selling unit decode stored_at + name', () {
      final product = Product.fromJson(_productJson());

      expect(product.storedAtId, 2);
      expect(product.storedAtName, 'Bodega');
      expect(product.variants.single.storedAtId, 2);
      expect(product.variants.single.storedAtName, 'Bodega');
      expect(product.variants.single.sellingUoms.single.storedAtId, 2);
      expect(product.variants.single.sellingUoms.single.storedAtName, 'Bodega');
    });

    test('a pre-B4 body reads as "no location", not id 0 / a fake name', () {
      final product = Product.fromJson(_productJson(withStoredAt: false));

      expect(product.storedAtId, isNull);
      expect(product.storedAtName, isEmpty);
      expect(product.variants.single.storedAtId, isNull);
      expect(product.variants.single.storedAtName, isEmpty);
      expect(product.variants.single.sellingUoms.single.storedAtName, isEmpty);
    });
  });

  group('sale lines carry the pick-up point the sale recorded', () {
    test('the sale response names where each line is picked up', () {
      final line = PosCheckoutResult.fromJson({
        'id': 18,
        'transaction_no': 'TRX-20261112-0007',
        'trans_date': '2026-11-12T10:00:00Z',
        'grand_total': '900.00',
        'receipt': {'or_number': 'OR-20261112-0007'},
        'items': [
          {
            'id': 1,
            'variant_uom': 11,
            'qty': '2.00',
            'unit_price': '450.00',
            'subtotal': '900.00',
            'stored_at': 2,
            'stored_at_name': 'Bodega',
          },
        ],
      }).lines.single;

      expect(line.storedAtName, 'Bodega');
    });

    test('a line with no stored_at_name decodes as "not stated"', () {
      // A sale written before B4: the receipt must print no caption at all
      // rather than naming a place the customer was never told.
      final line = PosCheckoutResult.fromJson({
        'id': 19,
        'transaction_no': 'TRX-20261112-0008',
        'trans_date': '2026-11-12T10:00:00Z',
        'grand_total': '450.00',
        'receipt': {'or_number': 'OR-20261112-0008'},
        'items': [
          {
            'id': 2,
            'variant_uom': 11,
            'qty': '1.00',
            'unit_price': '450.00',
            'subtotal': '450.00',
          },
        ],
      }).lines.single;

      expect(line.storedAtName, isEmpty);
    });
  });

  group('delivery slip items carry their own pick-up point (B4)', () {
    test('a slip item decodes stored_at_name', () {
      final item = DeliveryItem.fromJson({
        'name': 'Portland Cement',
        'unit': 'BAG',
        'qty': '2.00',
        'stored_at': 2,
        'stored_at_name': 'Bodega',
      });

      expect(item.storedAtName, 'Bodega');
    });

    test('a blank or absent name is null, which hides the caption', () {
      final item = DeliveryItem.fromJson({
        'name': 'Portland Cement',
        'unit': 'BAG',
        'qty': '2.00',
        'stored_at_name': '   ',
      });

      expect(item.storedAtName, isNull);
    });
  });

  group('a sale line keeps its place through the receipt', () {
    test('PosCartLine carries storedAtName across copyWith', () {
      const line = PosCartLine(
        variantUomId: 11,
        productName: 'Portland Cement',
        variantName: '40 kg',
        quantity: 2,
        unit: 'BAG',
        unitPrice: 450,
        availableQuantity: 10,
        storedAtName: 'Bodega',
      );

      expect(line.copyWith(quantity: 3).storedAtName, 'Bodega');
    });
  });
}
