// Tests for the catalogue assembler — the join that turns API entities into
// rows a catalogue screen can render.
//
// Why this exists: neither GET /api/v1/products/ nor GET /api/v1/variants/
// exposes a price or a stock quantity (verified against the running API), so
// the client must join:
//   price        = VariantUom.defaultSellingPrice       (decision 08 — the charged price)
//   stockOnHand  = sum of `/stock-on-hand/` qty rows     (Phase 9 F1, decision 21 §5)
// InventoryBatch.batchSellingPrice is deliberately NOT the price, and a batch is
// no longer a quantity authority: the server answers the per-location split.

import 'package:client/data/models/product.dart';
import 'package:client/data/models/stock_on_hand.dart';
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

VariantUom _uom({int id = 8, int variantId = 8, double price = 315}) {
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

Product _product({
  int id = 6,
  String name = 'Circuit Breaker',
  List<ProductVariant> variants = const [],
}) {
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

/// One `/stock-on-hand/` row: a variant's quantity on ONE shelf.
StockOnHand _onHand({
  int variantId = 6,
  double qty = 100,
  int locationId = 1,
  String locationName = 'Store',
  bool isHome = true,
}) {
  return StockOnHand(
    variantId: variantId,
    locationId: locationId,
    locationName: locationName,
    locationActive: true,
    isHome: isHome,
    qty: qty,
  );
}

void main() {
  group('assembleCatalogue', () {
    test('takes the charged price from the selling uom, not the batch', () {
      final items = assembleCatalogue(
        products: [
          _product(
            variants: [
              _variant(sellingUoms: [_uom(price: 315)]),
            ],
          ),
        ],
        stockOnHand: [_onHand(variantId: 8)],
      );

      expect(items, hasLength(1));
      // Decision 08: the batch price (180) must never be charged.
      expect(items.single.price, 315);
    });

    test('sums the quantity across the shelves the server lists', () {
      final items = assembleCatalogue(
        products: [
          _product(
            variants: [
              _variant(sellingUoms: [_uom()]),
            ],
          ),
        ],
        stockOnHand: [
          _onHand(variantId: 8, qty: 100),
          _onHand(
            variantId: 8,
            qty: 40,
            locationId: 2,
            locationName: 'Bodega',
            isHome: false,
          ),
        ],
      );

      expect(items.single.stockOnHand, 140);
    });

    test('ignores rows belonging to other variants', () {
      final items = assembleCatalogue(
        products: [
          _product(
            variants: [
              _variant(id: 8, sellingUoms: [_uom()]),
            ],
          ),
        ],
        stockOnHand: [
          _onHand(variantId: 8, qty: 10),
          _onHand(variantId: 999, qty: 500),
        ],
      );

      expect(items.single.stockOnHand, 10);
    });

    test('reports zero stock when the on-hand read lists no shelf', () {
      final items = assembleCatalogue(
        products: [
          _product(
            variants: [
              _variant(sellingUoms: [_uom()]),
            ],
          ),
        ],
        stockOnHand: const [],
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
        stockOnHand: const [],
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
        stockOnHand: [_onHand(variantId: 8)],
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
        stockOnHand: const [],
      );

      expect(items.single.product.baseName, 'Circuit Breaker');
      expect(items.single.variant.variantName, '20A 1-pole');
      expect(items.single.uom.uomCode, 'PC');
      expect(product.baseName, 'Circuit Breaker');
    });

    test('walks several products and variants', () {
      final items = assembleCatalogue(
        products: [
          _product(
            id: 1,
            variants: [
              _variant(
                id: 10,
                productId: 1,
                sellingUoms: [_uom(variantId: 10)],
              ),
              _variant(
                id: 11,
                productId: 1,
                sellingUoms: [_uom(variantId: 11)],
              ),
            ],
          ),
          _product(
            id: 2,
            variants: [
              _variant(
                id: 12,
                productId: 2,
                sellingUoms: [_uom(variantId: 12)],
              ),
            ],
          ),
        ],
        stockOnHand: [_onHand(variantId: 11, qty: 7)],
      );

      expect(items, hasLength(3));
      expect(items.where((i) => i.stockOnHand == 7).single.variant.id, 11);
    });
  });
}
