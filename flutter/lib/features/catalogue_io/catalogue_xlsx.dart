// Phase 3 Task F1: the .xlsx bytes.
//
// `excel_community` writes the workbook and gives us bytes; the file reaches the
// disk (or the browser download) through the same `file_selector` +
// `XFile.saveTo` path the barcode CSV already uses, never through the package's
// own download helper. One place builds cells, so the three rules the round trip
// depends on cannot drift per column:
//
//   - IDs, unit codes and barcodes are TEXT cells, so Excel keeps `0012345678905`
//     instead of turning it into `12345678905`;
//   - prices, factors and thresholds are NUMBERS, so a storekeeper can sort and
//     total them;
//   - every text value goes through `spreadsheetSafeText`, so a name beginning `=`
//     opens as text and does not run.

import 'dart:typed_data';

import 'package:client/core/format/spreadsheet_text.dart';
import 'package:client/features/catalogue_io/catalogue_sheet.dart';
import 'package:excel_community/excel_community.dart';

/// Sheet 1: one row per selling unit. F2 reads this one.
const catalogueSheetName = 'Catalogue';

/// Sheet 2: the values the by-name columns accept.
const catalogueListsSheetName = 'Lists';

/// The four lists of the Lists sheet, one column each.
const catalogueListsHeaders = <String>[
  'Category',
  'Unit code',
  'Stored at',
  'Brand',
];

/// The whole workbook as bytes, ready for a save dialog.
Uint8List catalogueXlsxBytes({
  required List<CatalogueSheetRow> rows,
  required CatalogueSheetLists lists,
}) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', catalogueSheetName);

  final sheet = excel[catalogueSheetName];
  sheet.appendRow([for (final header in catalogueSheetHeaders) _text(header)]);
  for (final row in rows) {
    sheet.appendRow(_cellsOf(row));
  }

  final listSheet = excel[catalogueListsSheetName];
  listSheet.appendRow([for (final header in catalogueListsHeaders) _text(header)]);
  final columns = lists.columns;
  final longest = columns.fold<int>(0, (longest, column) => column.length > longest ? column.length : longest);
  for (var index = 0; index < longest; index++) {
    listSheet.appendRow([
      for (final column in columns)
        index < column.length ? _text(column[index]) : null,
    ]);
  }

  final bytes = excel.encode();
  // `encode()` answers null only for a workbook it cannot serialise; refusing
  // beats saving an empty file over the user's chosen name.
  if (bytes == null) {
    throw StateError('Could not encode the catalogue workbook.');
  }
  return Uint8List.fromList(bytes);
}

/// One data row, column for column with [catalogueSheetHeaders].
List<CellValue?> _cellsOf(CatalogueSheetRow row) => [
  _text('${row.productId}'),
  _text('${row.variantId}'),
  _text('${row.unitId}'),
  _text(row.category),
  _text(row.brand),
  _text(row.productName),
  _text(row.variantName),
  _text(row.unitCode),
  _number(row.unitsPerBase),
  _number(row.price),
  _text(row.barcode),
  _number(row.lowStockThreshold),
  _text(row.storedAt),
  _text(row.active ? 'Yes' : 'No'),
];

CellValue _text(String value) => TextCellValue(spreadsheetSafeText(value));

/// A number cell: a whole value stays whole, so `1` and `40` do not become
/// `1.0` and `40.0` in a price column somebody reads.
CellValue _number(double value) {
  final isWhole = value == value.roundToDouble() && value.abs() < 1e15;
  return isWhole ? IntCellValue(value.toInt()) : DoubleCellValue(value);
}
