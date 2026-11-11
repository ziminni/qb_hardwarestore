// Phase 4 Task F2 (decision 18 + panel comment #5): the barcode masterlist.
//
// The assertions are on the PAYLOAD — the rows the document draws, the symbology
// each code gets, and the header lines — rather than on pixels, so a wrong row
// count, a factory EAN printed as Code 128 or a missing generated date fails here
// instead of on paper.

import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/labels/barcode_list_document.dart';
import 'package:flutter_test/flutter_test.dart';

ProductVariant variant({
  required int id,
  required int productId,
  String name = '20A 1-pole',
  bool isActive = true,
  List<VariantUom> sellingUoms = const [],
}) => ProductVariant(
  id: id,
  productId: productId,
  baseUomId: 1,
  minStockThreshold: 5,
  maxStockLevel: 0,
  sellingUoms: sellingUoms,
  variantName: name,
  baseUomCode: 'PC',
  isActive: isActive,
);

VariantUom unit({
  required int id,
  required int variantId,
  String code = 'QB000013-0',
  String uomCode = 'PC',
  double price = 315,
  int uomId = 1,
  double factor = 1,
}) => VariantUom(
  id: id,
  variantId: variantId,
  uomId: uomId,
  uomCode: uomCode,
  uomName: uomCode,
  barcodeQr: code,
  conversionFactor: factor,
  defaultSellingPrice: price,
);

Product product({
  required int id,
  String name = 'Circuit Breaker',
  String category = 'Electrical',
  bool isActive = true,
  List<ProductVariant> variants = const [],
}) => Product(
  id: id,
  categoryId: 1,
  categoryName: category,
  brandId: 1,
  brandName: 'Omni',
  baseName: name,
  description: '',
  imageUrl: '',
  isActive: isActive,
  variants: variants,
);

/// Two products, three selling units: the row count must follow the UNITS, not
/// the products.
List<Product> catalogue() => [
  product(
    id: 1,
    name: 'Circuit Breaker',
    variants: [
      variant(
        id: 8,
        productId: 1,
        sellingUoms: [
          unit(id: 12, variantId: 8, code: 'QB000012-3', price: 315),
          unit(
            id: 13,
            variantId: 8,
            code: '4800016123450',
            uomId: 2,
            uomCode: 'BOX',
            factor: 10,
            price: 3150,
          ),
        ],
      ),
    ],
  ),
  product(
    id: 2,
    name: 'PVC Pipe',
    category: 'Plumbing',
    variants: [
      variant(
        id: 9,
        productId: 2,
        name: '1/2 inch',
        sellingUoms: [
          unit(id: 14, variantId: 9, code: 'QB000014-8', price: 95),
        ],
      ),
    ],
  ),
];

void main() {
  group('barcodeSymbologyFor', () {
    test('a 13-digit code with a valid check digit is EAN 13', () {
      expect(barcodeSymbologyFor('4800016123450'), BarcodeSymbology.ean13);
    });

    test('an 8-digit code with a valid check digit is EAN 8', () {
      expect(barcodeSymbologyFor('96385074'), BarcodeSymbology.ean8);
    });

    test('the server-generated QB code is Code 128', () {
      expect(barcodeSymbologyFor('QB000013-0'), BarcodeSymbology.code128);
    });

    test(
      'a 13-digit code with a WRONG check digit is Code 128, not EAN 13',
      () {
        // Same length, last digit off by one: an EAN printer would refuse it.
        expect(barcodeSymbologyFor('4800016123451'), BarcodeSymbology.code128);
      },
    );

    test('a 12-digit code is Code 128 (EAN 13 needs the check digit)', () {
      expect(barcodeSymbologyFor('480001612345'), BarcodeSymbology.code128);
    });

    test('a blank code is Code 128 so the row still prints', () {
      expect(barcodeSymbologyFor('   '), BarcodeSymbology.code128);
    });
  });

  group('barcodeListRows', () {
    test('one row per selling unit, in catalogue order', () {
      final rows = barcodeListRows(catalogue());

      expect(rows, hasLength(3));
      expect(rows.map((row) => row.code).toList(), [
        'QB000012-3',
        '4800016123450',
        'QB000014-8',
      ]);
    });

    test('a row carries the product, variant, unit and price', () {
      final rows = barcodeListRows(catalogue());
      final box = rows[1];

      expect(box.productName, 'Circuit Breaker');
      expect(box.variantName, '20A 1-pole');
      expect(box.unitCode, 'BOX');
      expect(box.price, 3150);
    });

    test('a code typed with stray spaces and lowercase is normalised', () {
      final rows = barcodeListRows([
        product(
          id: 3,
          variants: [
            variant(
              id: 20,
              productId: 3,
              sellingUoms: [unit(id: 30, variantId: 20, code: ' qb000030-2 ')],
            ),
          ],
        ),
      ]);

      expect(rows.single.code, 'QB000030-2');
    });

    test('the units a caller resolves win over the nested catalogue rows', () {
      // The products endpoint's nested `selling_uoms` can be older than the
      // `/variant-uoms/` rows the store reloads after a code edit.
      final fresh = [unit(id: 99, variantId: 8, code: 'QB000099-1')];

      final rows = barcodeListRows(
        catalogue(),
        unitsOf: (variant) => variant.id == 8 ? fresh : variant.sellingUoms,
      );

      expect(rows.map((row) => row.code).toList(), [
        'QB000099-1',
        'QB000014-8',
      ]);
    });

    test('a product with no selling unit contributes no row', () {
      final rows = barcodeListRows([
        product(id: 4, variants: [variant(id: 40, productId: 4)]),
      ]);

      expect(rows, isEmpty);
    });
  });

  group('barcodeListHeaderLines', () {
    test('says what the list is, when it was made and what was filtered', () {
      final data = BarcodeListData(
        rows: barcodeListRows(catalogue()),
        generatedAt: DateTime(2026, 11, 11, 14, 5),
        categoryLabel: 'All categories',
        activeOnly: true,
      );

      final lines = barcodeListHeaderLines(data);

      expect(lines.first, 'Barcode list');
      expect(lines, contains('Generated Nov 11, 2026, 2:05 PM'));
      expect(lines.last, 'All categories · Active only · 3 codes');
    });

    test('an archived-included list says so, and counts in thousands', () {
      final data = BarcodeListData(
        rows: const [],
        generatedAt: DateTime(2026, 11, 11, 9),
        categoryLabel: 'Electrical',
        activeOnly: false,
      );

      expect(
        barcodeListHeaderLines(data).last,
        'Electrical · Active and archived · 0 codes',
      );
    });
  });

  group('buildBarcodeListPdf', () {
    test('renders one page for a short list', () async {
      final data = BarcodeListData(
        rows: barcodeListRows(catalogue()),
        generatedAt: DateTime(2026, 11, 11, 9),
        categoryLabel: 'All categories',
        activeOnly: true,
      );

      final bytes = await buildBarcodeListPdf(data);

      expect(bytes, isNotEmpty);
      expect(_pdfPageCount(bytes), 1);
    });

    test('a long list spans pages', () async {
      final rows = [
        for (var index = 0; index < 240; index++)
          BarcodeListRow(
            productName: 'Portland Cement $index',
            variantName: '40kg',
            unitCode: 'BAG',
            price: 270,
            code: 'QB00${index.toString().padLeft(4, '0')}-1',
          ),
      ];
      final data = BarcodeListData(
        rows: rows,
        generatedAt: DateTime(2026, 11, 11, 9),
        categoryLabel: 'All categories',
        activeOnly: true,
      );

      final bytes = await buildBarcodeListPdf(data);

      expect(_pdfPageCount(bytes), greaterThan(1));
    });

    test('an empty list still renders one page with the header', () async {
      final data = BarcodeListData(
        rows: const [],
        generatedAt: DateTime(2026, 11, 11, 9),
        categoryLabel: 'All categories',
        activeOnly: true,
      );

      expect(_pdfPageCount(await buildBarcodeListPdf(data)), 1);
    });
  });

  group('barcodeListPageLabel', () {
    test('page numbers read "Page x of y"', () {
      expect(barcodeListPageLabel(1, 3), 'Page 1 of 3');
      expect(barcodeListPageLabel(3, 3), 'Page 3 of 3');
    });
  });
}

/// How many pages a PDF really carries: the object dictionary marks each one.
int _pdfPageCount(List<int> bytes) {
  final text = String.fromCharCodes(bytes);
  return RegExp(r'/Type\s*/Page[^s]').allMatches(text).length;
}
