// Tests for the catalogue assembler — the join that turns API entities into
// rows a catalogue screen can render.
//
// Why this exists: neither GET /api/v1/products/ nor GET /api/v1/variants/
// exposes a price or a stock quantity (verified against the running API), so
// the client must join:
//   price        = VariantUom.defaultSellingPrice   (decision 08 — the charged price)
//   stockOnHand  = sum(InventoryBatch.currentQty)   for the matching variant
// InventoryBatch.batchSellingPrice is deliberately NOT the price.

import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/services/catalogue_assembler.dart';
import 'package:flutter_test/flutter_test.dart';

ProductVariant _variant({
  int id = 8,
  int productId = 6,
  String name = '20A 1-pole',
  double minStockThreshold = 20,
  List<VariantUom> sellingUoms = const [],
}) {
  return ProductVariant(
    id: id,
    productId: productId,
    variantName: name,
    baseUomId: 2,
    baseUomCode: 'PC',
    minStockThreshold: minStockThreshold,
    maxStockLevel: 0,
    isActive: true,
    sellingUoms: sellingUoms,
  );
}

VariantUom _uom({
  int id = 8,
  int variantId = 8,
  double price = 315,
}) {
  return VariantUom(
    id: id,
    variantId: variantId,
    uomId: 2,
    uomCode: 'PC',
    uomName: 'Piece',
    barcodeQr: '',
    conversionFactor: 1,
    defaultSellingPrice: price,
  );
}

Product _product({int id = 6, String name = 'Circuit Breaker', List<ProductVariant> variants = const []}) {
  return Product(
    id: id,
    categoryId: 4,
    categoryName: 'Electrical',
    brandId: 4,
    brandName: 'Omni',
    baseName: name,
    description: '',
    imageUrl: '',
    isActive: true,
    variants: variants,
  );
}

InventoryBatch _batch({
  int id = 6,
  int variantId = 6,
  double currentQty = 100,
  double batchSellingPrice = 180,
}) {
  return InventoryBatch(
    id: id,
    variantId: variantId,
    receiptId: 6,
    initialQty: currentQty,
    currentQty: currentQty,
    unitCostLanded: 180,
    markupPercentage: 0,
    batchSellingPrice: batchSellingPrice,
    expirationDate: null,
    createdAt: null,
  );
}

void main() {
  group('assembleCatalogue', () {
    test('takes the charged price from the selling uom, not the batch', () {
      final items = assembleCatalogue(
        products: [
          _product(variants: [_variant(sellingUoms: [_uom(price: 315)])]),
        ],
        batches: [_batch(variantId: 8, batchSellingPrice: 180)],
      );

      expect(items, hasLength(1));
      // Decision 08: the batch price (180) must never be charged.
      expect(items.single.price, 315);
    });

    test('sums stock across every batch of the variant', () {
      final items = assembleCatalogue(
        products: [
          _product(variants: [_variant(sellingUoms: [_uom()])]),
        ],
        batches: [
          _batch(id: 1, variantId: 8, currentQty: 100),
          _batch(id: 2, variantId: 8, currentQty: 40),
        ],
      );

      expect(items.single.stockOnHand, 140);
    });

    test('ignores batches belonging to other variants', () {
      final items = assembleCatalogue(
        products: [
          _product(variants: [_variant(id: 8, sellingUoms: [_uom()])]),
        ],
        batches: [
          _batch(id: 1, variantId: 8, currentQty: 10),
          _batch(id: 2, variantId: 999, currentQty: 500),
        ],
      );

      expect(items.single.stockOnHand, 10);
    });

    test('reports zero stock when a variant has no batches', () {
      final items = assembleCatalogue(
        products: [
          _product(variants: [_variant(sellingUoms: [_uom()])]),
        ],
        batches: const [],
      );

      expect(items.single.stockOnHand, 0);
    });

    test('excludes a variant that has no selling unit configured', () {
      // A variant with no selling uom has no chargeable price, so it cannot be
      // sold. Excluding it is deliberate — the alternative is inventing a 0 price.
      final items = assembleCatalogue(
        products: [
          _product(variants: [_variant(sellingUoms: const [])]),
        ],
        batches: const [],
      );

      expect(items, isEmpty);
    });

    test('emits one row per selling unit', () {
      final items = assembleCatalogue(
        products: [
          _product(
            variants: [
              _variant(
                sellingUoms: [
                  _uom(id: 1, price: 315),
                  _uom(id: 2, price: 3000),
                ],
              ),
            ],
          ),
        ],
        batches: [_batch(variantId: 8, currentQty: 100)],
      );

      expect(items, hasLength(2));
      expect(items.map((i) => i.price), containsAll(<double>[315, 3000]));
      // Stock is a property of the variant, so both rows report the same figure.
      expect(items.every((i) => i.stockOnHand == 100), isTrue);
    });

    test('carries the product and variant onto each row', () {
      final product = _product(name: 'Circuit Breaker');
      final variant = _variant(sellingUoms: [_uom()]);

      final items = assembleCatalogue(
        products: [
          _product(variants: [variant]),
        ],
        batches: const [],
      );

      expect(items.single.product.baseName, 'Circuit Breaker');
      expect(items.single.variant.variantName, '20A 1-pole');
      expect(items.single.uom.uomCode, 'PC');
      expect(product.baseName, 'Circuit Breaker');
    });

    test('walks several products and variants', () {
      final items = assembleCatalogue(
        products: [
          _product(id: 1, variants: [
            _variant(id: 10, productId: 1, sellingUoms: [_uom(variantId: 10)]),
            _variant(id: 11, productId: 1, sellingUoms: [_uom(variantId: 11)]),
          ]),
          _product(id: 2, variants: [
            _variant(id: 12, productId: 2, sellingUoms: [_uom(variantId: 12)]),
          ]),
        ],
        batches: [
          _batch(id: 1, variantId: 11, currentQty: 7),
        ],
      );

      expect(items, hasLength(3));
      expect(
        items.where((i) => i.stockOnHand == 7).single.variant.id,
        11,
      );
    });
  });
}
