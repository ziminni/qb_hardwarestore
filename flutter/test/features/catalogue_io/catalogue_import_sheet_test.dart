// Phase 3 Task F2: reading the edited .xlsx back into the rows the server wants.
//
// The file is the contract between F1's writer and this parser, so the first test
// is the real round trip: F1's bytes in, the same values out, apostrophe escape
// undone and a leading-zero barcode intact. The rest are the ways a spreadsheet
// differs from the object model: numbers instead of text, columns somebody added,
// rows somebody emptied, and a workbook bigger than one import accepts.

import 'dart:typed_data';

import 'package:client/features/catalogue_io/catalogue_import_sheet.dart';
import 'package:client/features/catalogue_io/catalogue_sheet.dart';
import 'package:client/features/catalogue_io/catalogue_xlsx.dart';
import 'package:flutter_test/flutter_test.dart';

import 'catalogue_import_workbook.dart';

void main() {
  group('the round trip', () {
    test('F1 export parsed back gives the rows the export started from', () {
      const original = CatalogueSheetRow(
        productId: 6,
        variantId: 8,
        unitId: 11,
        category: 'Electrical',
        brand: 'Omni',
        productName: '=SUM(A1)',
        variantName: '20A 1-pole',
        unitCode: 'PC',
        unitsPerBase: 1,
        price: 315,
        // A factory code with leading zeros must come back digit for digit.
        barcode: '0012345678905',
        lowStockThreshold: 5,
        storedAt: 'Bodega',
        active: true,
      );

      final rows = parseCatalogueSheet(
        catalogueXlsxBytes(
          rows: const [original],
          lists: CatalogueSheetLists.empty(),
        ),
      );

      expect(rows, hasLength(1));
      expect(rows.single.values, {
        'product_id': '6',
        'variant_id': '8',
        'unit_id': '11',
        'category': 'Electrical',
        'brand': 'Omni',
        // The writer's apostrophe is undone, so the name is the one that was
        // exported, not the escaped copy.
        'product_name': '=SUM(A1)',
        'variant': '20A 1-pole',
        'unit_code': 'PC',
        'units_per_base': '1',
        'price': '315',
        'barcode': '0012345678905',
        'low_stock_threshold': '5',
        'stored_at': 'Bodega',
        'active': 'Yes',
      });
    });

    test('a fractional price and a forty-piece box survive too', () {
      final rows = parseCatalogueSheet(
        catalogueXlsxBytes(
          rows: const [
            CatalogueSheetRow(
              productId: 6,
              variantId: 8,
              unitId: 12,
              category: 'Electrical',
              brand: 'Omni',
              productName: 'Circuit Breaker',
              variantName: '20A 1-pole',
              unitCode: 'BOX',
              unitsPerBase: 40,
              price: 12000.5,
              barcode: 'QB000013-1',
              lowStockThreshold: 0,
              storedAt: 'Bodega',
              active: false,
            ),
          ],
          lists: CatalogueSheetLists.empty(),
        ),
      );

      expect(rows.single.values['units_per_base'], '40');
      expect(rows.single.values['price'], '12000.5');
      expect(rows.single.values['low_stock_threshold'], '0');
      expect(rows.single.values['active'], 'No');
    });

    test('the parser reads every header the export writes', () {
      expect(
        catalogueImportColumns.values.toSet(),
        catalogueSheetHeaders.toSet(),
      );
      expect(catalogueImportColumns, hasLength(catalogueSheetHeaders.length));
    });
  });

  group('the header row', () {
    test('a missing column is refused by name, once', () {
      final bytes = workbook(
        headers: [
          for (final header in catalogueSheetHeaders)
            if (header != 'Price') header,
        ],
        rows: [rowCells()..removeAt(9)],
      );

      expect(
        () => parseCatalogueSheet(bytes),
        throwsA(
          isA<CatalogueImportRefusal>().having(
            (refusal) => refusal.message,
            'message',
            allOf(contains('"Price"'), contains('export the catalogue again')),
          ),
        ),
      );
    });

    test('a renamed column is the same refusal', () {
      final bytes = workbook(
        headers: [
          for (final header in catalogueSheetHeaders)
            if (header == 'Price') 'Selling price' else header,
        ],
      );

      expect(
        () => parseCatalogueSheet(bytes),
        throwsA(
          isA<CatalogueImportRefusal>().having(
            (refusal) => refusal.message,
            'message',
            contains('"Price"'),
          ),
        ),
      );
    });

    test('a heading that appears twice is refused by name, once', () {
      // Two "Price" columns: taking either one would be a silent guess.
      final bytes = workbook(
        headers: [...catalogueSheetHeaders, 'price'],
        rows: [
          [...rowCells(), '320'],
        ],
      );

      expect(
        () => parseCatalogueSheet(bytes),
        throwsA(
          isA<CatalogueImportRefusal>().having(
            (refusal) => refusal.message,
            'message',
            allOf(
              contains('"Price"'),
              contains('two'),
              contains('import the file again'),
            ),
          ),
        ),
      );
    });

    test('a workbook with no Catalogue sheet is refused', () {
      final bytes = workbook(sheetName: 'Sheet1');

      expect(
        () => parseCatalogueSheet(bytes),
        throwsA(
          isA<CatalogueImportRefusal>().having(
            (refusal) => refusal.message,
            'message',
            contains('"Catalogue"'),
          ),
        ),
      );
    });

    test('bytes that are not a workbook are refused, not a crash', () {
      expect(
        () => parseCatalogueSheet(Uint8List.fromList([1, 2, 3, 4])),
        throwsA(isA<CatalogueImportRefusal>()),
      );
    });
  });

  group('the cells', () {
    test('extra columns are ignored', () {
      final rows = parseCatalogueSheet(
        workbook(
          headers: [...catalogueSheetHeaders, 'Notes'],
          rows: [
            [...rowCells(), 'typed by the clerk'],
          ],
        ),
      );

      expect(rows.single.values.keys, catalogueImportColumns.keys);
      expect(rows.single.values.values, isNot(contains('typed by the clerk')));
    });

    test('numbers arrive as text with no dangling decimal', () {
      final rows = parseCatalogueSheet(
        workbook(
          rows: [
            rowCells(unitsPerBase: 12.0, price: 12.5, lowStockThreshold: 3),
          ],
        ),
      );

      expect(rows.single.values['units_per_base'], '12');
      expect(rows.single.values['price'], '12.5');
      expect(rows.single.values['low_stock_threshold'], '3');
    });

    test('a TRUE / FALSE cell becomes the word the server accepts', () {
      final rows = parseCatalogueSheet(
        workbook(
          rows: [
            rowCells(productId: '6', active: true),
            rowCells(productId: '7', active: false),
          ],
        ),
      );

      expect(rows[0].values['active'], 'TRUE');
      expect(rows[1].values['active'], 'FALSE');
    });

    test('the export apostrophe is undone only before a formula start', () {
      final rows = parseCatalogueSheet(
        workbook(
          rows: [
            rowCells(productName: "'=SUM(A1)", variant: "'@risk"),
            rowCells(productId: '7', productName: "'Cement", variant: "'-tag"),
          ],
        ),
      );

      expect(rows[0].values['product_name'], '=SUM(A1)');
      expect(rows[0].values['variant'], '@risk');
      // A genuine leading apostrophe stays: nothing follows it that Excel would
      // have run. Before a formula start the file cannot tell the two apart.
      expect(rows[1].values['product_name'], "'Cement");
      expect(rows[1].values['variant'], '-tag');
    });

    test('a blank id cell stays blank, so the row is a create', () {
      final rows = parseCatalogueSheet(
        workbook(
          rows: [rowCells(productId: '', variantId: '', unitId: '')],
        ),
      );

      expect(rows.single.values['product_id'], '');
      expect(rows.single.values['variant_id'], '');
      expect(rows.single.values['unit_id'], '');
    });
  });

  group('the row list', () {
    test('fully empty rows are skipped, in the middle and at the end', () {
      final rows = parseCatalogueSheet(
        workbook(
          rows: [
            rowCells(),
            List<Object?>.filled(catalogueSheetHeaders.length, ''),
            rowCells(productId: '7'),
            const <Object?>[],
            List<Object?>.filled(catalogueSheetHeaders.length, null),
          ],
        ),
      );

      expect(rows, hasLength(2));
      expect(rows.map((row) => row.values['product_id']), ['6', '7']);
    });

    test('each kept row knows the spreadsheet row it came from', () {
      final rows = parseCatalogueSheet(
        workbook(
          rows: [
            rowCells(),
            emptiedRow(),
            rowCells(productId: '7'),
          ],
        ),
      );

      // The heading is row 1, so the two kept rows are sheet rows 2 and 4: the
      // emptied row still counts in the file even though it is not sent.
      expect(rows.map((row) => row.sheetRow), [2, 4]);
    });

    test('a header row and nothing else is zero rows, not a refusal', () {
      expect(parseCatalogueSheet(workbook()), isEmpty);
    });

    test('more than 2,000 rows is refused before anything is sent', () {
      final bytes = workbook(
        rows: [
          for (var index = 0; index <= catalogueImportMaxRows; index++)
            ['${index + 1}'],
        ],
      );

      expect(
        () => parseCatalogueSheet(bytes),
        throwsA(
          isA<CatalogueImportRefusal>().having(
            (refusal) => refusal.message,
            'message',
            allOf(contains('2,000'), contains('split')),
          ),
        ),
      );
    });

    test('exactly 2,000 rows is accepted', () {
      final rows = parseCatalogueSheet(
        workbook(
          rows: [
            for (var index = 0; index < catalogueImportMaxRows; index++)
              ['${index + 1}'],
          ],
        ),
      );

      expect(rows, hasLength(catalogueImportMaxRows));
      expect(rows.last.values['product_id'], '2000');
    });
  });
}
