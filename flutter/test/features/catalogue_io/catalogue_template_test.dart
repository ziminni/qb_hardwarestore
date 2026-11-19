// Owner 2026-11-18: the bulk-import template on the Import & export page.
//
// Pinned: it is the catalogue workbook (same headings, read back by the same
// parser), its example rows have BLANK ids (so the import creates them), each
// example variant has exactly one Units per base 1 row, the names come from this
// shop's own lists, and it carries a "How to fill" sheet. A server preview of a
// template built from the dev catalogue's lists answered 0 errors (2026-11-18).

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:client/features/catalogue_io/catalogue_import_sheet.dart';
import 'package:client/features/catalogue_io/catalogue_sheet.dart';
import 'package:client/features/catalogue_io/catalogue_xlsx.dart';
import 'package:excel_community/excel_community.dart';
import 'package:flutter_test/flutter_test.dart';

const _lists = CatalogueSheetLists(
  categories: ['Aggregates', 'Cement', 'Masonry'],
  unitCodes: ['BAG', 'CU.M', 'KG', 'PACK', 'PC'],
  locations: ['Bodega', 'Store'],
  brands: ['Local Supply', 'Rhino'],
);

void main() {
  final bytes = catalogueXlsxBytes(
    rows: catalogueTemplateRows(_lists),
    lists: _lists,
    instructions: catalogueTemplateInstructions,
  );

  test('the template reads back as create rows with blank ids', () {
    final rows = parseCatalogueSheet(bytes);
    expect(rows, isNotEmpty);
    for (final row in rows) {
      expect(row.values['product_id'], '');
      expect(row.values['variant_id'], '');
      expect(row.values['unit_id'], '');
    }
  });

  test('every example variant has exactly one base row', () {
    final rows = catalogueTemplateRows(_lists);
    final byVariant = <String, int>{};
    for (final row in rows) {
      final key = '${row.productName}|${row.variantName}';
      byVariant[key] = (byVariant[key] ?? 0) + (row.unitsPerBase == 1 ? 1 : 0);
    }
    expect(byVariant.values, everyElement(1));
  });

  test('the example names all come from the shop lists', () {
    for (final row in catalogueTemplateRows(_lists)) {
      expect(_lists.categories, contains(row.category));
      expect(_lists.brands, contains(row.brand));
      expect(_lists.unitCodes, contains(row.unitCode));
      expect(_lists.locations, contains(row.storedAt));
    }
  });

  test('the workbook carries the Lists and How to fill sheets', () {
    final excel = Excel.decodeBytes(bytes);
    expect(
      excel.tables.keys,
      containsAll([
        catalogueSheetName,
        catalogueListsSheetName,
        catalogueInstructionsSheetName,
      ]),
    );
  });

  test('the Catalogue sheet carries dropdowns, number checks and a frozen '
      'heading row', () {
    final archive = ZipDecoder().decodeBytes(bytes);
    final sheet = utf8.decode(
      archive.findFile('xl/worksheets/sheet1.xml')!.content,
    );
    // Dropdowns fed by the Lists sheet: Category (A), Brand (D), Unit code
    // (B), Stored at (C), sized to the lists above.
    const q = "'";
    for (final (column, range) in [
      ('D', r'$A$2:$A$4'),
      ('E', r'$D$2:$D$3'),
      ('H', r'$B$2:$B$6'),
      ('M', r'$C$2:$C$3'),
    ]) {
      expect(
        sheet,
        contains(
          'sqref="${column}2:${column}2001"><formula1>${q}Lists$q!$range',
        ),
      );
    }
    expect(sheet, contains('&quot;Yes,No&quot;'));
    expect(sheet, contains('type="decimal" operator="greaterThan"'));
    expect(sheet, contains('state="frozen"'));
    // The tips and checks change nothing the import reads.
    expect(parseCatalogueSheet(bytes), hasLength(4));
  });

  test('an export still writes its ids', () {
    final row = parseCatalogueSheet(
      catalogueXlsxBytes(
        rows: const [
          CatalogueSheetRow(
            productId: 6,
            variantId: 8,
            unitId: 9,
            category: 'Cement',
            brand: 'Rhino',
            productName: 'Portland Cement',
            variantName: '40kg',
            unitCode: 'BAG',
            unitsPerBase: 1,
            price: 260,
            barcode: '',
            lowStockThreshold: 5,
            storedAt: 'Store',
            active: true,
          ),
        ],
        lists: _lists,
      ),
    ).single;
    expect(
      (
        row.values['product_id'],
        row.values['variant_id'],
        row.values['unit_id'],
      ),
      ('6', '8', '9'),
    );
  });
}
