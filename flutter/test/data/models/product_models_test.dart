// Wire-contract tests for the product-hierarchy models.
//
// Every payload below is copied from the LIVE API (seed_demo data), not invented.
// Contract facts these tests lock in, verified by probing the running stack:
//   - all decimals arrive as JSON **strings** ("315.00", "100.00"), never numbers
//   - `expiration_date` is nullable; `barcode_qr` / `description` may be ""
//   - variant and uom references are integer ids, not nested objects
//
// Decision 02: a missing *required* field must throw, not silently become 0.

import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VariantUom.fromJson', () {
    // GET /api/v1/variant-uoms/ (live)
    final livePayload = <String, dynamic>{
      'id': 8,
      'variant': 8,
      'uom': 2,
      'uom_code': 'PC',
      'uom_name': 'Piece',
      'barcode_qr': '',
      'conversion_factor': '1.00',
      'default_selling_price': '315.00',
    };

    test('parses decimals from strings', () {
      final uom = VariantUom.fromJson(livePayload);

      expect(uom.id, 8);
      expect(uom.variantId, 8);
      expect(uom.uomCode, 'PC');
      expect(uom.uomName, 'Piece');
      expect(uom.barcodeQr, '');
      expect(uom.conversionFactor, 1.00);
      expect(uom.defaultSellingPrice, 315.00);
    });

    test('throws when default_selling_price is missing', () {
      final payload = Map<String, dynamic>.from(livePayload)
        ..remove('default_selling_price');

      expect(() => VariantUom.fromJson(payload), throwsFormatException);
    });
  });

  group('InventoryBatch.fromJson', () {
    // GET /api/v1/batches/ (live) — expiration_date is null for this batch
    final livePayload = <String, dynamic>{
      'id': 6,
      'variant': 6,
      'receipt': 6,
      'initial_qty': '100.00',
      'current_qty': '100.00',
      'unit_cost_landed': '180.00',
      'markup_percentage': '0.00',
      'batch_selling_price': '180.00',
      'expiration_date': null,
      'created_at': '2026-09-25T11:30:00+08:00',
    };

    test('parses quantities and costs from strings', () {
      final batch = InventoryBatch.fromJson(livePayload);

      expect(batch.id, 6);
      expect(batch.variantId, 6);
      expect(batch.initialQty, 100.00);
      expect(batch.currentQty, 100.00);
      expect(batch.unitCostLanded, 180.00);
      expect(batch.batchSellingPrice, 180.00);
    });

    test('allows a null expiration date', () {
      final batch = InventoryBatch.fromJson(livePayload);

      expect(batch.expirationDate, isNull);
    });

    test('parses a present expiration date', () {
      final payload = Map<String, dynamic>.from(livePayload)
        ..['expiration_date'] = '2027-01-31';

      expect(InventoryBatch.fromJson(payload).expirationDate, isNotNull);
    });

    test('throws when current_qty is missing', () {
      final payload = Map<String, dynamic>.from(livePayload)
        ..remove('current_qty');

      expect(() => InventoryBatch.fromJson(payload), throwsFormatException);
    });
  });

  group('ProductVariant.fromJson', () {
    // GET /api/v1/variants/ (live) — nesting includes selling_uoms
    final livePayload = <String, dynamic>{
      'id': 8,
      'product': 6,
      'variant_name': '20A 1-pole',
      'base_uom': 2,
      'base_uom_code': 'PC',
      'min_stock_threshold': '20.00',
      'max_stock_level': '0.00',
      'is_active': true,
      'selling_uoms': [
        {
          'id': 8,
          'variant': 8,
          'uom': 2,
          'uom_code': 'PC',
          'uom_name': 'Piece',
          'barcode_qr': '',
          'conversion_factor': '1.00',
          'default_selling_price': '315.00',
        },
      ],
      'created_at': '2026-09-25T11:30:00+08:00',
      'updated_at': '2026-09-25T11:30:00+08:00',
    };

    test('parses the variant exactly as the API sends it', () {
      final variant = ProductVariant.fromJson(livePayload);

      expect(variant.id, 8);
      expect(variant.productId, 6);
      expect(variant.variantName, '20A 1-pole');
      expect(variant.baseUomCode, 'PC');
      expect(variant.minStockThreshold, 20.00);
      expect(variant.maxStockLevel, 0.00);
      expect(variant.isActive, isTrue);
      expect(variant.sellingUoms, hasLength(1));
      expect(variant.sellingUoms.single.defaultSellingPrice, 315.00);
    });

    test('carries no stock or price of its own', () {
      // The API exposes neither on a variant, so a variant with no selling_uoms
      // still parses — price and stock are the catalogue assembler's job.
      final payload = Map<String, dynamic>.from(livePayload)
        ..['selling_uoms'] = <dynamic>[];

      final variant = ProductVariant.fromJson(payload);

      expect(variant.sellingUoms, isEmpty);
    });

    test('throws when variant_name is missing', () {
      // The old model defaulted this class of field to '' or 0, which is how a
      // variant silently rendered as PHP 0.00.
      final payload = Map<String, dynamic>.from(livePayload)
        ..remove('variant_name');

      expect(() => ProductVariant.fromJson(payload), throwsFormatException);
    });

    test('throws when min_stock_threshold is missing', () {
      final payload = Map<String, dynamic>.from(livePayload)
        ..remove('min_stock_threshold');

      expect(() => ProductVariant.fromJson(payload), throwsFormatException);
    });
  });

  group('Product.fromJson', () {
    // GET /api/v1/products/ (live) — variants arrive nested
    final livePayload = <String, dynamic>{
      'id': 6,
      'category': 4,
      'category_name': 'Electrical',
      'brand': 4,
      'brand_name': 'Omni',
      'base_name': 'Circuit Breaker',
      'description': '',
      'image_url': '',
      'is_active': true,
      'variants': [
        {
          'id': 8,
          'product': 6,
          'variant_name': '20A 1-pole',
          'base_uom': 2,
          'base_uom_code': 'PC',
          'min_stock_threshold': '20.00',
          'max_stock_level': '0.00',
          'is_active': true,
          'selling_uoms': <dynamic>[],
        },
      ],
      'created_at': '2026-09-25T11:30:00+08:00',
      'updated_at': '2026-09-25T11:30:00+08:00',
    };

    test('keeps parsing, including nested variants', () {
      final product = Product.fromJson(livePayload);

      expect(product.id, 6);
      expect(product.categoryName, 'Electrical');
      expect(product.brandName, 'Omni');
      expect(product.baseName, 'Circuit Breaker');
      expect(product.isActive, isTrue);
      expect(product.variants, hasLength(1));
      expect(product.variants.single.variantName, '20A 1-pole');
    });
  });

  group('ProductVariant.barcode', () {
    // Decision 10: there is no SKU field in the backend. The SKU column becomes a
    // Barcode column fed by VariantUom.barcode_qr, derived here so any widget can
    // read it without reaching into the selling-unit list itself.
    Map<String, dynamic> variantJson(List<Map<String, dynamic>> uoms) => {
      'id': 8,
      'variant_name': '20A 1-pole',
      'base_uom_code': 'PC',
      'product': 6,
      'base_uom': 1,
      'min_stock_threshold': '20.00',
      'max_stock_level': '0.00',
      'selling_uoms': uoms,
    };

    test('reads the barcode off the first selling unit that has one', () {
      final variant = ProductVariant.fromJson(
        variantJson([
          {
            'id': 8,
            'variant': 8,
            'uom': 1,
            'uom_code': 'PC',
            'uom_name': 'Piece',
            'barcode_qr': 'MAT-00001',
            'conversion_factor': '1.00',
            'default_selling_price': '315.00',
          },
        ]),
      );

      expect(variant.barcode, 'MAT-00001');
    });

    test('is empty when no selling unit carries one', () {
      // The honest seeded state: barcode_qr is '' in every live row.
      final variant = ProductVariant.fromJson(
        variantJson([
          {
            'id': 8,
            'variant': 8,
            'uom': 1,
            'uom_code': 'PC',
            'uom_name': 'Piece',
            'barcode_qr': '',
            'conversion_factor': '1.00',
            'default_selling_price': '315.00',
          },
        ]),
      );

      expect(variant.barcode, '');
    });

    test('is empty when the variant has no selling unit at all', () {
      expect(ProductVariant.fromJson(variantJson([])).barcode, '');
    });
  });
}
