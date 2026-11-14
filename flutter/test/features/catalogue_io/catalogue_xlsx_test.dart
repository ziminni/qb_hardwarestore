// Phase 3 Task F1: the .xlsx bytes the user saves.
//
// The file is written and then decoded again here, because the two things that
// would quietly ruin a round trip are invisible in the object model: a barcode
// stored as a number loses its leading zeros, and an unescaped sheet name is a
// formula that runs when the file opens. Both are asserted on the DECODED cells.

import 'dart:typed_data';

import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/catalogue_io/catalogue_sheet.dart';
import 'package:client/features/catalogue_io/catalogue_xlsx.dart';
import 'package:excel_community/excel_community.dart';
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

Product catalogueProduct({
  String name = 'Circuit Breaker',
  String variantName = '20A 1-pole',
  String barcode = 'QB000013-0',
  double price = 315,
  double factor = 1,
}) => Product(
  id: 6,
  categoryId: 3,
  categoryName: 'Electrical',
  brandId: 1,
  brandName: 'Omni',
  baseName: name,
  description: '',
  imageUrl: '',
  isActive: true,
  storedAtName: 'Bodega',
  variants: [
    ProductVariant(
      id: 8,
      productId: 6,
      baseUomId: 1,
      minStockThreshold: 5,
      maxStockLevel: 0,
      variantName: variantName,
      baseUomCode: 'PC',
      isActive: true,
      sellingUoms: [
        unit(
          id: 11,
          variantId: 8,
          barcode: barcode,
          price: price,
          factor: factor,
        ),
      ],
    ),
  ],
);

CatalogueSheetLists defaultLists() => CatalogueSheetLists.fromSources(
  categories: const [Category(id: 3, name: 'Electrical')],
  units: const [
    UnitOfMeasure(id: 1, code: 'PC', name: 'Piece'),
    UnitOfMeasure(id: 2, code: 'BOX', name: 'Box'),
  ],
  locations: const [StorageLocation(id: 1, name: 'Bodega')],
  brands: const [Brand(id: 1, name: 'Omni')],
);

/// The exported file, decoded back the way F2 and Excel read it.
Excel encoded({List<Product>? products, CatalogueSheetLists? lists}) =>
    Excel.decodeBytes(
      catalogueXlsxBytes(
        rows: catalogueSheetRows(products ?? [catalogueProduct()]),
        lists: lists ?? defaultLists(),
      ),
    );

/// The decoded cell text of one row, columns in sheet order.
List<String> cellsOf(Sheet sheet, int rowIndex) => [
  for (final cell in sheet.rows[rowIndex]) cell?.value?.toString() ?? '',
];

void main() {
  group('catalogueXlsxBytes', () {
    test('is a real xlsx with a Catalogue sheet and a Lists sheet', () {
      final excel = encoded();

      expect(excel.tables.keys, containsAll(['Catalogue', 'Lists']));
      expect(excel.tables.keys, hasLength(2));
    });

    test('row 1 is the header, in the pinned order', () {
      final sheet = encoded()['Catalogue'];

      expect(cellsOf(sheet, 0), catalogueSheetHeaders);
    });

    test('the sheet name is the lowercase-safe one the app will look for', () {
      expect(catalogueSheetName, 'Catalogue');
      expect(catalogueListsSheetName, 'Lists');
    });

    test('the header names are text cells, not formulas', () {
      final sheet = encoded()['Catalogue'];

      expect(sheet.rows[0].first?.value, isA<TextCellValue>());
    });

    test('one data row per selling unit, under the header', () {
      final sheet = encoded(
        products: [
          catalogueProduct(),
          catalogueProduct(
            name: 'PVC Pipe',
            variantName: '1/2 inch',
            barcode: 'QB000014-8',
            price: 95.5,
          ),
        ],
      )['Catalogue'];

      // header + two unit rows
      expect(sheet.rows, hasLength(3));
      expect(cellsOf(sheet, 2)[5], 'PVC Pipe');
    });

    test('a leading-zero barcode decodes as TEXT, zeros intact', () {
      final sheet = encoded(
        products: [catalogueProduct(barcode: '0012345678905')],
      )['Catalogue'];
      final cell = sheet.rows[1][10];

      expect(cell?.value.toString(), '0012345678905');
      expect(cell?.value, isA<TextCellValue>());
      expect(cell?.value, isNot(isA<IntCellValue>()));
      expect(cell?.value, isNot(isA<DoubleCellValue>()));
    });

    test('ids and unit codes decode as text, so Excel shows them as typed', () {
      final sheet = encoded()['Catalogue'];
      final row = sheet.rows[1];

      for (final index in const [0, 1, 2, 7]) {
        expect(row[index]?.value, isA<TextCellValue>());
      }
      expect(row[0]?.value.toString(), '6');
      expect(row[1]?.value.toString(), '8');
      expect(row[2]?.value.toString(), '11');
      expect(row[7]?.value.toString(), 'PC');
    });

    test('prices, factors and thresholds decode as numbers', () {
      final sheet = encoded(
        products: [catalogueProduct(price: 315.5, factor: 40)],
      )['Catalogue'];
      final row = sheet.rows[1];

      expect(row[8]?.value, isNot(isA<TextCellValue>())); // Units per base
      expect(row[9]?.value, isNot(isA<TextCellValue>())); // Price
      expect(row[11]?.value, isNot(isA<TextCellValue>())); // Threshold
      expect(row[8]?.value.toString(), '40');
      expect(row[9]?.value.toString(), '315.5');
      expect(row[11]?.value.toString(), '5');
    });

    test('a formula-like product name is escaped and stays literal text', () {
      final sheet = encoded(
        products: [catalogueProduct(name: '=SUM(A1)', variantName: '@SUM(A1)')],
      )['Catalogue'];

      expect(cellsOf(sheet, 1)[5], "'=SUM(A1)");
      expect(cellsOf(sheet, 1)[6], "'@SUM(A1)");
      expect(sheet.rows[1][5]?.value, isA<TextCellValue>());
      expect(sheet.rows[1][5]?.value, isNot(isA<FormulaCellValue>()));
    });

    test('Active is written as Yes / No and decodes as text', () {
      final active = encoded()['Catalogue'];
      final archived = encoded(
        products: [
          Product(
            id: 7,
            categoryId: 3,
            categoryName: 'Electrical',
            brandId: 1,
            brandName: 'Omni',
            baseName: 'Old breaker',
            description: '',
            imageUrl: '',
            isActive: false,
            storedAtName: 'Bodega',
            variants: catalogueProduct().variants,
          ),
        ],
      )['Catalogue'];

      expect(active.rows[1][13]?.value.toString(), 'Yes');
      expect(archived.rows[1][13]?.value.toString(), 'No');
      expect(archived.rows[1][13]?.value, isA<TextCellValue>());
    });

    test('Stored at and Brand come from the product', () {
      final sheet = encoded()['Catalogue'];
      final row = cellsOf(sheet, 1);

      expect(row[3], 'Electrical');
      expect(row[4], 'Omni');
      expect(row[12], 'Bodega');
    });
  });

  group('the Lists sheet', () {
    test('names the four lists in one header row and fills them below', () {
      final lists = encoded()['Lists'];

      expect(cellsOf(lists, 0), [
        'Category',
        'Unit code',
        'Stored at',
        'Brand',
      ]);
      expect(cellsOf(lists, 1), ['Electrical', 'BOX', 'Bodega', 'Omni']);
      expect(cellsOf(lists, 2), ['', 'PC', '', '']);
    });

    test('carries only the active locations and categories', () {
      final lists = encoded(
        lists: CatalogueSheetLists.fromSources(
          categories: const [
            Category(id: 1, name: 'Electrical'),
            Category(id: 2, name: 'Gone', isActive: false),
          ],
          units: const [UnitOfMeasure(id: 1, code: 'PC', name: 'Piece')],
          locations: const [
            StorageLocation(id: 1, name: 'Bodega'),
            StorageLocation(id: 2, name: 'Old shelf', isActive: false),
          ],
          brands: const [Brand(id: 1, name: 'Omni')],
        ),
      )['Lists'];

      final texts = [
        for (var index = 0; index < lists.rows.length; index++)
          ...cellsOf(lists, index),
      ];
      expect(texts, isNot(contains('Gone')));
      expect(texts, isNot(contains('Old shelf')));
    });
  });

  group('the exported bytes', () {
    test('are a xlsx (zip) payload and not empty', () {
      final bytes = catalogueXlsxBytes(
        rows: catalogueSheetRows([catalogueProduct()]),
        lists: defaultLists(),
      );

      expect(bytes, isA<Uint8List>());
      expect(bytes.length, greaterThan(1000));
      // ZIP local file header: PK\x03\x04
      expect(bytes.sublist(0, 2), [0x50, 0x4B]);
    });

    test('an empty catalogue still produces a header-only file', () {
      final excel = Excel.decodeBytes(
        catalogueXlsxBytes(rows: const [], lists: defaultLists()),
      );

      expect(cellsOf(excel['Catalogue'], 0), catalogueSheetHeaders);
      expect(excel['Catalogue'].rows, hasLength(1));
    });
  });
}
