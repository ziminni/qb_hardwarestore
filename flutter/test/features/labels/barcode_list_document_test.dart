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

    test(
      'groups by category alphabetically and sorts items alphabetically inside each category',
      () {
        final unsorted = [
          product(
            id: 10,
            name: 'PVC Elbow',
            category: 'Plumbing',
            variants: [
              variant(
                id: 100,
                productId: 10,
                name: '1 inch',
                sellingUoms: [unit(id: 1, variantId: 100, code: 'QB000100-1')],
              ),
            ],
          ),
          product(
            id: 11,
            name: 'Angle Valve',
            category: 'Plumbing',
            variants: [
              variant(
                id: 101,
                productId: 11,
                name: '1/2 inch',
                sellingUoms: [unit(id: 2, variantId: 101, code: 'QB000101-1')],
              ),
            ],
          ),
          product(
            id: 12,
            name: 'THHN Wire',
            category: 'Electrical',
            variants: [
              variant(
                id: 102,
                productId: 12,
                name: '#12 Red',
                sellingUoms: [unit(id: 3, variantId: 102, code: 'QB000102-1')],
              ),
            ],
          ),
          product(
            id: 13,
            name: 'Breaker Box',
            category: 'Electrical',
            variants: [
              variant(
                id: 103,
                productId: 13,
                name: '4-Branch',
                sellingUoms: [unit(id: 4, variantId: 103, code: 'QB000103-1')],
              ),
            ],
          ),
          product(
            id: 14,
            name: 'Loose Bolts',
            category: '',
            variants: [
              variant(
                id: 104,
                productId: 14,
                name: 'M8',
                sellingUoms: [unit(id: 5, variantId: 104, code: 'QB000104-1')],
              ),
            ],
          ),
        ];

        final rows = barcodeListRows(unsorted);

        expect(
          rows.map((r) => '${r.displayCategory}:${r.productName}').toList(),
          [
            'Electrical:Breaker Box',
            'Electrical:THHN Wire',
            'Plumbing:Angle Valve',
            'Plumbing:PVC Elbow',
            'Uncategorized:Loose Bolts',
          ],
        );
      },
    );
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

  group('barcodeBookletPages', () {
    test('splits rows into 10-card (2x5) booklet pages', () {
      final rows = [
        for (var i = 0; i < 23; i++)
          BarcodeListRow(
            productName: 'Item $i',
            variantName: 'Standard',
            unitCode: 'PC',
            price: 100,
            code: 'QB0000${i.toString().padLeft(2, '0')}-1',
          ),
      ];

      final pages = barcodeBookletPages(rows);

      expect(pages, hasLength(3));
      expect(pages[0], hasLength(barcodeBookletItemsPerPage));
      expect(pages[1], hasLength(barcodeBookletItemsPerPage));
      expect(pages[2], hasLength(3));
    });

    test('an empty list still yields one booklet page for the header', () {
      final pages = barcodeBookletPages(const []);
      expect(pages, hasLength(1));
      expect(pages.single, isEmpty);
    });
  });

  group('barcodeBookletLayoutPages', () {
    test('groups All categories into A-Z category sections with banners', () {
      final data = BarcodeListData(
        rows: const [
          BarcodeListRow(
            productName: 'PVC Pipe',
            variantName: '1/2 inch',
            unitCode: 'PC',
            price: 95,
            code: 'QB000001-1',
            categoryName: 'Plumbing',
          ),
          BarcodeListRow(
            productName: 'Wire',
            variantName: '#14',
            unitCode: 'M',
            price: 25,
            code: 'QB000002-1',
            categoryName: 'Electrical',
          ),
          BarcodeListRow(
            productName: 'Adapter',
            variantName: '20A',
            unitCode: 'PC',
            price: 45,
            code: 'QB000003-1',
            categoryName: 'Electrical',
          ),
        ],
        generatedAt: DateTime(2026, 11, 11, 9),
        categoryLabel: 'All categories',
        activeOnly: true,
      );

      final pages = barcodeBookletLayoutPages(data);

      expect(pages, hasLength(1));
      final sections = pages.single;
      expect(sections.map((s) => s.categoryName).toList(), [
        'Electrical',
        'Plumbing',
      ]);
      expect(sections.every((s) => s.showHeader), isTrue);
      expect(sections.first.rows.map((r) => r.productName).toList(), [
        'Adapter',
        'Wire',
      ]);
    });

    test('continues a large category across pages with a continuation banner', () {
      final data = BarcodeListData(
        rows: [
          for (var i = 0; i < 12; i++)
            BarcodeListRow(
              productName: 'Item ${i.toString().padLeft(2, '0')}',
              variantName: 'Std',
              unitCode: 'PC',
              price: 50,
              code: 'QB0000${i.toString().padLeft(2, '0')}-1',
              categoryName: 'Electrical',
            ),
          const BarcodeListRow(
            productName: 'Elbow',
            variantName: '1/2 inch',
            unitCode: 'PC',
            price: 20,
            code: 'QB000099-1',
            categoryName: 'Plumbing',
          ),
        ],
        generatedAt: DateTime(2026, 11, 11, 9),
        categoryLabel: 'All categories',
        activeOnly: true,
      );

      final pages = barcodeBookletLayoutPages(data);

      expect(pages, hasLength(2));
      expect(pages[0].single.categoryName, 'Electrical');
      expect(pages[0].single.isContinuation, isFalse);
      expect(pages[0].single.rows, hasLength(10));
      expect(pages[1].map((s) => s.categoryName).toList(), [
        'Electrical',
        'Plumbing',
      ]);
      expect(pages[1][0].isContinuation, isTrue);
      expect(pages[1][0].rows, hasLength(2));
      expect(pages[1][1].isContinuation, isFalse);
      expect(pages[1][1].rows, hasLength(1));
    });

    test('specific category omits redundant category banners and sorts A-Z', () {
      final data = BarcodeListData(
        rows: const [
          BarcodeListRow(
            productName: 'Switch',
            variantName: '1-gang',
            unitCode: 'PC',
            price: 60,
            code: 'QB000002-1',
            categoryName: 'Electrical',
          ),
          BarcodeListRow(
            productName: 'Breaker',
            variantName: '20A',
            unitCode: 'PC',
            price: 315,
            code: 'QB000001-1',
            categoryName: 'Electrical',
          ),
        ],
        generatedAt: DateTime(2026, 11, 11, 9),
        categoryLabel: 'Electrical',
        activeOnly: true,
      );

      final pages = barcodeBookletLayoutPages(data);

      expect(pages, hasLength(1));
      expect(pages.single.single.showHeader, isFalse);
      expect(pages.single.single.rows.map((r) => r.productName).toList(), [
        'Breaker',
        'Switch',
      ]);
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

    test('fits 10 booklet cards on one page and rolls the 11th to page 2', () async {
      List<BarcodeListRow> makeRows(int count) => [
        for (var i = 0; i < count; i++)
          BarcodeListRow(
            productName: 'Heavy Duty Electrical Conduit Pipe $i',
            variantName: '20mm x 3m Schedule 40',
            unitCode: 'PC',
            price: 185.5,
            code: 'QB000${i.toString().padLeft(3, '0')}-1',
          ),
      ];

      final tenBytes = await buildBarcodeListPdf(
        BarcodeListData(
          rows: makeRows(barcodeBookletItemsPerPage),
          generatedAt: DateTime(2026, 11, 11, 9),
          categoryLabel: 'Electrical',
          activeOnly: true,
        ),
      );
      final elevenBytes = await buildBarcodeListPdf(
        BarcodeListData(
          rows: makeRows(barcodeBookletItemsPerPage + 1),
          generatedAt: DateTime(2026, 11, 11, 9),
          categoryLabel: 'Electrical',
          activeOnly: true,
        ),
      );

      expect(_pdfPageCount(tenBytes), 1);
      expect(_pdfPageCount(elevenBytes), 2);
    });

    test('a long list spans pages at 10 cards per booklet page', () async {
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

      expect(_pdfPageCount(bytes), 24);
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

    test(
      'renders 10 long-name cards on one page with bundled OpenSans (all categories grouped)',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final data = BarcodeListData(
          rows: [
            for (var i = 0; i < barcodeBookletItemsPerPage; i++)
              BarcodeListRow(
                productName:
                    'Industrial Heavy Duty Galvanized Steel Pipe Coupling #$i',
                variantName: '25mm Schedule 40 Threaded',
                unitCode: i.isEven ? 'PC' : 'BOX',
                price: 1245.75,
                code: i == 0
                    ? '4800016123450'
                    : 'QB000${i.toString().padLeft(3, '0')}-1',
                categoryName: 'Plumbing',
              ),
          ],
          generatedAt: DateTime(2026, 11, 11, 9),
          categoryLabel: 'All categories',
          activeOnly: true,
        );

        final bytes = await buildBarcodeListPdfWithOpenSans(data);

        expect(bytes, isNotEmpty);
        expect(_pdfPageCount(bytes), 1);
      },
    );
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
