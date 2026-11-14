// Phase 3 Task F1: the catalogue sheet's columns and row mapping.
//
// The sheet is the contract the import (F2, and the server's preview/apply) reads
// back by header NAME, so the order and the spelling of every heading are pinned
// here: a rename that nobody notices would make every uploaded row a refusal.
// Decision 23 fixes the columns; the owner ruling of 2026-11-12 adds Brand.

import 'package:client/core/format/spreadsheet_text.dart';
import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/catalogue_io/catalogue_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

VariantUom unit({
  required int id,
  required int variantId,
  String code = 'PC',
  String barcode = 'QB000013-0',
  double factor = 1,
  double price = 315,
}) => VariantUom(
  id: id,
  variantId: variantId,
  uomId: id,
  uomCode: code,
  uomName: code,
  barcodeQr: barcode,
  conversionFactor: factor,
  defaultSellingPrice: price,
);

ProductVariant variant({
  required int id,
  required int productId,
  String name = '20A 1-pole',
  double threshold = 5,
  List<VariantUom> sellingUoms = const [],
}) => ProductVariant(
  id: id,
  productId: productId,
  baseUomId: 1,
  minStockThreshold: threshold,
  maxStockLevel: 0,
  variantName: name,
  baseUomCode: 'PC',
  isActive: true,
  sellingUoms: sellingUoms,
);

Product product({
  int id = 6,
  String category = 'Electrical',
  String brand = 'Omni',
  String name = 'Circuit Breaker',
  bool isActive = true,
  String storedAt = 'Bodega',
  List<ProductVariant> variants = const [],
}) => Product(
  id: id,
  categoryId: 3,
  categoryName: category,
  brandId: 1,
  brandName: brand,
  baseName: name,
  description: '',
  imageUrl: '',
  isActive: isActive,
  storedAtName: storedAt,
  variants: variants,
);

void main() {
  group('catalogueSheetHeaders', () {
    test('is decision 23 order plus Brand, and nothing else', () {
      expect(catalogueSheetHeaders, const [
        'Product ID',
        'Variant ID',
        'Unit ID',
        'Category',
        'Brand',
        'Product name',
        'Variant',
        'Unit code',
        'Units per base',
        'Price',
        'Barcode',
        'Low-stock threshold',
        'Stored at',
        'Active',
      ]);
    });
  });

  group('catalogueSheetRows', () {
    test('one row per selling unit, ids and values carried through', () {
      final rows = catalogueSheetRows([
        product(
          variants: [
            variant(
              id: 8,
              productId: 6,
              sellingUoms: [
                unit(id: 11, variantId: 8),
                unit(
                  id: 12,
                  variantId: 8,
                  code: 'BOX',
                  barcode: 'QB000013-1',
                  factor: 40,
                  price: 12000,
                ),
              ],
            ),
          ],
        ),
      ]);

      expect(rows, hasLength(2));
      expect(
        rows.map((row) => (row.unitId, row.unitCode, row.unitsPerBase)),
        [(11, 'PC', 1.0), (12, 'BOX', 40.0)],
      );
      expect(rows.first.productId, 6);
      expect(rows.first.variantId, 8);
      expect(rows.last.price, 12000);
    });

    test('product-level facts repeat on every unit row', () {
      final rows = catalogueSheetRows([
        product(
          variants: [
            variant(
              id: 8,
              productId: 6,
              sellingUoms: [
                unit(id: 11, variantId: 8),
                unit(id: 12, variantId: 8, code: 'BOX', factor: 40),
              ],
            ),
          ],
        ),
      ]);

      for (final row in rows) {
        expect(row.category, 'Electrical');
        expect(row.brand, 'Omni');
        expect(row.productName, 'Circuit Breaker');
        expect(row.storedAt, 'Bodega');
        expect(row.active, isTrue);
      }
    });

    test('the threshold is the variant\'s, on each of its units', () {
      final rows = catalogueSheetRows([
        product(
          variants: [
            variant(
              id: 8,
              productId: 6,
              threshold: 12.5,
              sellingUoms: [unit(id: 11, variantId: 8)],
            ),
          ],
        ),
      ]);

      expect(rows.single.lowStockThreshold, 12.5);
    });

    test('an archived product is exported with Active false', () {
      final rows = catalogueSheetRows([
        product(
          isActive: false,
          variants: [
            variant(
              id: 8,
              productId: 6,
              sellingUoms: [unit(id: 11, variantId: 8)],
            ),
          ],
        ),
      ]);

      expect(rows.single.active, isFalse);
    });

    test('a leading-zero barcode is kept digit for digit', () {
      final rows = catalogueSheetRows([
        product(
          variants: [
            variant(
              id: 8,
              productId: 6,
              sellingUoms: [
                unit(id: 11, variantId: 8, barcode: '0012345678905'),
              ],
            ),
          ],
        ),
      ]);

      expect(rows.single.barcode, '0012345678905');
    });

    test('a product with no selling unit contributes no rows', () {
      final rows = catalogueSheetRows([
        product(variants: [variant(id: 8, productId: 6)]),
      ]);

      expect(rows, isEmpty);
    });

    test('unitsOf wins over the nested units (they can be older)', () {
      final stale = product(
        variants: [
          variant(
            id: 8,
            productId: 6,
            sellingUoms: [unit(id: 11, variantId: 8, price: 315)],
          ),
        ],
      );
      final fresh = variant(
        id: 8,
        productId: 6,
        sellingUoms: [unit(id: 11, variantId: 8, price: 350)],
      );

      final rows = catalogueSheetRows(
        [stale],
        unitsOf: (variant) => fresh.sellingUoms,
      );

      expect(rows.single.price, 350);
    });
  });

  group('catalogueSheetLists', () {
    test('carries active categories, unit codes, active locations and brands', () {
      final lists = CatalogueSheetLists.fromSources(
        categories: const [
          Category(id: 3, name: 'Plumbing'),
          Category(id: 1, name: 'Electrical'),
          Category(id: 2, name: 'Archived', isActive: false),
        ],
        units: const [
          UnitOfMeasure(id: 2, code: 'PC', name: 'Piece'),
          UnitOfMeasure(id: 1, code: 'BOX', name: 'Box'),
        ],
        locations: const [
          StorageLocation(id: 1, name: 'Bodega'),
          StorageLocation(id: 2, name: 'Old shelf', isActive: false),
        ],
        brands: const [
          Brand(id: 1, name: 'Omni'),
          Brand(id: 2, name: 'Kanto'),
        ],
      );

      expect(lists.categories, ['Electrical', 'Plumbing']);
      expect(lists.unitCodes, ['BOX', 'PC']);
      expect(lists.locations, ['Bodega']);
      expect(lists.brands, ['Kanto', 'Omni']);
    });
  });

  // The escape is shared with the barcode-list CSV (OWASP spreadsheet injection):
  // a name Excel would treat as a formula gets a leading apostrophe.
  group('spreadsheetSafeText', () {
    for (final trigger in ['=', '+', '-', '@', '\t', '\r']) {
      test('a value starting with ${trigger.codeUnitAt(0)} gains an apostrophe', () {
        expect(spreadsheetSafeText('${trigger}SUM(A1)'), "'${trigger}SUM(A1)");
      });
    }

    test('an ordinary name and an empty string are left alone', () {
      expect(spreadsheetSafeText('Pump = duty'), 'Pump = duty');
      expect(spreadsheetSafeText(''), '');
    });
  });
}
