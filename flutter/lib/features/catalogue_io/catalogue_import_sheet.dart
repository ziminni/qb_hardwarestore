// Phase 3 Task F2: the edited .xlsx read back as rows for the server.
//
// The export (F1) is the other half of this contract: sheet 1 named "Catalogue",
// one row per selling unit, the headings in `catalogueSheetHeaders` order. Here we
// find the sheet, read the headings BY NAME (so a clerk can move a column and the
// import still works, and a renamed heading is one clear refusal instead of a
// silently wrong column), and hand back one map per row, keyed the way
// `catalogue_import.COLUMNS` on the server expects.
//
// Three things a spreadsheet does that the object model does not:
//
//   - a number comes back as a number (`12` is fine, `12.0` is not what the server
//     reads), so whole values are written without a decimal;
//   - the export marks a formula-like text with a leading apostrophe so Excel does
//     not run it, and the mark has to come off again on the way back in;
//   - rows somebody emptied are still rows in the file, and sending them would be
//     sending 2,000 row errors about blank cells.
//
// Nothing here validates the catalogue: what a row may say is the server's rule
// (one set of rules, decision 23). This file only shapes cells into strings.

import 'dart:typed_data';

import 'package:client/core/format/format.dart';
import 'package:client/core/format/spreadsheet_text.dart';
import 'package:client/features/catalogue_io/catalogue_xlsx.dart';
import 'package:excel_community/excel_community.dart';

/// Decision 23: up to 2,000 rows per file. A bigger sheet is refused HERE, before
/// anything goes over the wire, so the clerk waits for a sentence and not for a
/// request the server will not read.
const catalogueImportMaxRows = 2000;

/// Sheet column heading -> the row key the server reads (`catalogue_import.COLUMNS`
/// in `backend_django/apps/inventory/catalogue_import.py`). The heading is what the
/// clerk sees and what the export writes; the key never leaves the wire.
const catalogueImportColumns = <String, String>{
  'product_id': 'Product ID',
  'variant_id': 'Variant ID',
  'unit_id': 'Unit ID',
  'category': 'Category',
  'brand': 'Brand',
  'product_name': 'Product name',
  'variant': 'Variant',
  'unit_code': 'Unit code',
  'units_per_base': 'Units per base',
  'price': 'Price',
  'barcode': 'Barcode',
  'low_stock_threshold': 'Low-stock threshold',
  'stored_at': 'Stored at',
  'active': 'Active',
};

/// A file this app cannot read as a catalogue sheet, worded for the clerk and
/// ending in what to do next.
class CatalogueImportRefusal implements Exception {
  const CatalogueImportRefusal(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One kept row: the values the server reads, and the spreadsheet row they came
/// from.
///
/// [sheetRow] is the number in Excel's row gutter, the heading being row 1, so a
/// clerk fixing an error looks at the cell the server meant even when the rows
/// somebody emptied were skipped on the way out. It stays beside [values] rather
/// than in the map: the payload has to keep the exact keys the server reads.
class CatalogueImportRow {
  const CatalogueImportRow({required this.sheetRow, required this.values});

  final int sheetRow;
  final Map<String, String> values;
}

/// Sheet 1's data rows, fully empty ones dropped, as the rows the preview takes.
List<CatalogueImportRow> parseCatalogueSheet(Uint8List bytes) {
  final excel = _decode(bytes);
  final sheet = excel.tables[catalogueSheetName];
  if (sheet == null || sheet.rows.isEmpty) {
    throw const CatalogueImportRefusal(
      'That workbook has no "Catalogue" sheet: export the catalogue again and '
      'edit the file the export gave you.',
    );
  }

  final headers = sheet.rows.first;
  final headingIndex = <String, int>{};
  final repeated = <String>{};
  for (var index = 0; index < headers.length; index++) {
    final heading = _cellText(headers[index]?.value).trim().toLowerCase();
    if (heading.isEmpty) continue;
    if (headingIndex.containsKey(heading)) repeated.add(heading);
    headingIndex[heading] = index;
  }

  final columns = <String, int>{};
  for (final entry in catalogueImportColumns.entries) {
    final heading = entry.value.toLowerCase();
    final index = headingIndex[heading];
    if (index == null) {
      throw CatalogueImportRefusal(
        'That sheet has no "${entry.value}" column: export the catalogue again '
        'and edit the file the export gave you.',
      );
    }
    // Two columns with one heading: reading the last one would be a silent guess
    // about which cells the clerk meant, so say which heading is doubled.
    if (repeated.contains(heading)) {
      throw CatalogueImportRefusal(
        'That sheet has two "${entry.value}" columns: delete one and import the '
        'file again.',
      );
    }
    columns[entry.key] = index;
  }

  final rows = <CatalogueImportRow>[];
  // Index 0 is the heading; `+ 1` turns the 0-based row list into the 1-based
  // row number Excel shows, and emptied rows still count in both.
  for (var index = 1; index < sheet.rows.length; index++) {
    final cells = sheet.rows[index];
    final values = <String, String>{};
    var isEmpty = true;
    for (final entry in columns.entries) {
      final cellIndex = entry.value;
      final text = _cellText(
        cellIndex < cells.length ? cells[cellIndex]?.value : null,
      );
      values[entry.key] = text;
      if (text.trim().isNotEmpty) isEmpty = false;
    }
    if (!isEmpty) {
      rows.add(CatalogueImportRow(sheetRow: index + 1, values: values));
    }
  }

  if (rows.length > catalogueImportMaxRows) {
    throw CatalogueImportRefusal(
      '${formatCount(rows.length)} rows is more than the '
      '${formatCount(catalogueImportMaxRows)} rows one import accepts: split the '
      'sheet into files of at most ${formatCount(catalogueImportMaxRows)} rows and '
      'import them one at a time.',
    );
  }
  return rows;
}

Excel _decode(Uint8List bytes) {
  try {
    return Excel.decodeBytes(bytes);
  } catch (_) {
    throw const CatalogueImportRefusal(
      'That file is not an Excel workbook: export the catalogue again and edit '
      'the file the export gave you.',
    );
  }
}

/// One cell as the text the server reads.
///
/// Text is un-escaped here, once, so a name the export marked as formula-like
/// arrives as the name the clerk typed. A number keeps its digits: `12.0` from a
/// re-saved file is the `12` the export wrote.
String _cellText(CellValue? value) => switch (value) {
  null => '',
  IntCellValue(:final value) => '$value',
  DoubleCellValue(:final value) => _numberText(value),
  // Excel hands a boolean Active back as TRUE / FALSE, which the server accepts.
  BoolCellValue(:final value) => value ? 'TRUE' : 'FALSE',
  // A real formula: its text is what the clerk typed, so that is what is sent.
  FormulaCellValue(:final formula) => spreadsheetLiteralText(formula),
  TextCellValue(:final value) => spreadsheetLiteralText('$value'),
  _ => spreadsheetLiteralText('$value'),
};

String _numberText(double value) =>
    value == value.roundToDouble() && value.abs() < 1e15
    ? '${value.toInt()}'
    : '$value';
