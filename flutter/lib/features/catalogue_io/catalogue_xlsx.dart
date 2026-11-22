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

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:client/core/format/spreadsheet_text.dart';
import 'package:client/features/catalogue_io/catalogue_sheet.dart';
import 'package:excel_community/excel_community.dart';

/// Sheet 1: one row per selling unit. F2 reads this one.
const catalogueSheetName = 'Catalogue';

/// Sheet 2: the values the by-name columns accept.
const catalogueListsSheetName = 'Lists';

/// Sheet 3 of the import TEMPLATE only: how to fill it in.
const catalogueInstructionsSheetName = 'How to fill';

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
  List<String> instructions = const [],
}) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', catalogueSheetName);

  final sheet = excel[catalogueSheetName];
  sheet.appendRow([for (final header in catalogueSheetHeaders) _text(header)]);
  _styleHeadings(sheet);
  for (final row in rows) {
    sheet.appendRow(_cellsOf(row));
  }

  final listSheet = excel[catalogueListsSheetName];
  listSheet.appendRow([
    for (final header in catalogueListsHeaders) _text(header),
  ]);
  for (var column = 0; column < catalogueListsHeaders.length; column++) {
    listSheet.setColumnWidth(column, 22);
    listSheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0))
        .cellStyle = _headingStyle(
      _gold,
    );
  }
  final columns = lists.columns;
  final longest = columns.fold<int>(
    0,
    (longest, column) => column.length > longest ? column.length : longest,
  );
  for (var index = 0; index < longest; index++) {
    listSheet.appendRow([
      for (final column in columns)
        index < column.length ? _text(column[index]) : null,
    ]);
  }

  // The import template's "How to fill" sheet. The import reads sheet 1 only.
  if (instructions.isNotEmpty) {
    final help = excel[catalogueInstructionsSheetName];
    for (final line in instructions) {
      help.appendRow([_text(line)]);
    }
    help.setColumnWidth(0, 120);
    help
        .cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0))
        .cellStyle = _headingStyle(
      _gold,
    );
  }

  final bytes = excel.encode();
  // `encode()` answers null only for a workbook it cannot serialise; refusing
  // beats saving an empty file over the user's chosen name.
  if (bytes == null) {
    throw StateError('Could not encode the catalogue workbook.');
  }
  return _withDropdowns(Uint8List.fromList(bytes), lists);
}

// ---------------------------------------------------------------------------
// Making the sheet friendly (owner 2026-11-18)
// ---------------------------------------------------------------------------

/// The rows the dropdowns and number checks cover: the import's 2,000-row
/// limit below the heading.
const _lastDataRow = 2001;

const _gold = '#E1C684';
const _grey = '#D9D9D9';
const _sand = '#F3EFE5';

/// Column widths, in characters, in [catalogueSheetHeaders] order.
const _widths = <double>[
  11, 11, 11, 18, 18, 28, 16, 12, 14, 12, 18, 18, 14, 10, //
];

/// The ID columns are the system's; required on a NEW row are Category,
/// Brand, Product name, Variant, Unit code, Units per base and Price.
const _idColumns = {0, 1, 2};
const _requiredColumns = {3, 4, 5, 6, 7, 8, 9};

CellStyle _headingStyle(String fill) => CellStyle(
  bold: true,
  backgroundColorHex: ExcelColor.fromHexString(fill),
  textWrapping: TextWrapping.WrapText,
);

void _styleHeadings(Sheet sheet) {
  for (var column = 0; column < catalogueSheetHeaders.length; column++) {
    sheet.setColumnWidth(column, _widths[column]);
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: column, rowIndex: 0))
        .cellStyle = _headingStyle(
      _idColumns.contains(column)
          ? _grey
          : _requiredColumns.contains(column)
          ? _gold
          : _sand,
    );
  }
}

String _columnLetter(int index) => String.fromCharCode(65 + index);

/// Escapes text for an XML attribute.
String _attr(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('"', '&quot;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

/// One `<dataValidation>`: a dropdown or number rule on one column, with the
/// tip Excel shows when a cell is selected and the message for a wrong value.
String _rule({
  required int column,
  required String type,
  String? operator,
  required String formula,
  required String title,
  required String tip,
  required String error,
}) {
  final letter = _columnLetter(column);
  return '<dataValidation type="$type"'
      '${operator == null ? '' : ' operator="$operator"'}'
      ' allowBlank="1" showInputMessage="1" showErrorMessage="1"'
      ' errorStyle="stop" errorTitle="${_attr(title)}"'
      ' error="${_attr(error)}" promptTitle="${_attr(title)}"'
      ' prompt="${_attr(tip)}" sqref="${letter}2:$letter$_lastDataRow">'
      '<formula1>${_attr(formula)}</formula1></dataValidation>';
}

/// A Lists-sheet range such as `'Lists'!$A$2:$A$9`, or null for an empty list.
String? _listRange(int listColumn, int length) {
  if (length == 0) return null;
  final letter = _columnLetter(listColumn);
  final dollar = String.fromCharCode(36);
  return "'$catalogueListsSheetName'!$dollar$letter${dollar}2:"
      '$dollar$letter$dollar${length + 1}';
}

/// Adds dropdowns, number checks, tips and a frozen heading row to the
/// Catalogue sheet.
///
/// `excel_community` cannot write data validation, so this edits the sheet's
/// XML inside the finished .xlsx (a zip of XML files). The import reads cell
/// VALUES only, so none of this changes what it sees.
Uint8List _withDropdowns(Uint8List bytes, CatalogueSheetLists lists) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final workbook = archive.findFile('xl/workbook.xml');
  final rels = archive.findFile('xl/_rels/workbook.xml.rels');
  if (workbook == null || rels == null) return bytes;
  final relId = RegExp(
    '<sheet[^>]*name="$catalogueSheetName"[^>]*r:id="([^"]+)"',
  ).firstMatch(utf8.decode(workbook.content))?.group(1);
  final target = relId == null
      ? null
      : RegExp(
          '<Relationship[^>]*Id="$relId"[^>]*Target="([^"]+)"',
        ).firstMatch(utf8.decode(rels.content))?.group(1);
  final sheetFile = target == null ? null : archive.findFile('xl/$target');
  if (sheetFile == null) return bytes;

  final dropdowns = [
    (3, 0, lists.categories, 'Category', 'Pick a category from the list.'),
    (4, 3, lists.brands, 'Brand', 'Pick a brand from the list.'),
    (
      7,
      1,
      lists.unitCodes,
      'Unit code',
      'On the base row this decides weight, length, volume or count.',
    ),
    (12, 2, lists.locations, 'Stored at', 'Store or Bodega.'),
  ];
  final rules = <String>[
    for (final (column, listColumn, values, title, tip) in dropdowns)
      if (_listRange(listColumn, values.length) case final range?)
        _rule(
          column: column,
          type: 'list',
          formula: range,
          title: title,
          tip: tip,
          error: 'Pick a $title from the list. New ones are added in the app.',
        ),
    _rule(
      column: 13,
      type: 'list',
      formula: '"Yes,No"',
      title: 'Active',
      tip: 'Yes to sell it, No to archive the whole product.',
      error: 'Choose Yes or No.',
    ),
    _rule(
      column: 8,
      type: 'decimal',
      operator: 'greaterThan',
      formula: '0',
      title: 'Units per base',
      tip: 'Type 1 for each product variant.',
      error: 'Units per base must be more than 0. Type 1 for each variant.',
    ),
    _rule(
      column: 9,
      type: 'decimal',
      operator: 'greaterThanOrEqual',
      formula: '0',
      title: 'Price',
      tip: 'Selling price of THIS unit, in pesos.',
      error: 'The price must be a number, 0 or more.',
    ),
    _rule(
      column: 11,
      type: 'decimal',
      operator: 'greaterThanOrEqual',
      formula: '0',
      title: 'Low-stock threshold',
      tip: 'Warn below this many base units. Same on every row of a product.',
      error: 'The threshold must be a number, 0 or more.',
    ),
    for (final column in _idColumns)
      _rule(
        column: column,
        type: 'whole',
        operator: 'greaterThan',
        formula: '0',
        title: 'Leave blank',
        tip: 'Filled by the system. Leave blank for a new product.',
        error: 'IDs come from the system: leave this blank for a new product.',
      ),
  ];

  var xml = utf8.decode(sheetFile.content);
  final validations =
      '<dataValidations count="${rules.length}">${rules.join()}'
      '</dataValidations>';
  final margins = xml.indexOf('<pageMargins');
  xml = margins >= 0
      ? xml.replaceRange(margins, margins, validations)
      : xml.replaceFirst('</worksheet>', '$validations</worksheet>');
  // Freeze the heading row so it stays on screen while scrolling.
  xml = xml.replaceFirstMapped(
    RegExp(r'<sheetView([^>]*)/>'),
    (m) =>
        '<sheetView${m[1]}><pane ySplit="1" topLeftCell="A2" '
        'activePane="bottomLeft" state="frozen"/></sheetView>',
  );

  final out = Archive();
  for (final file in archive.files) {
    if (file.name == sheetFile.name) {
      final content = utf8.encode(xml);
      out.addFile(ArchiveFile(file.name, content.length, content));
    } else {
      out.addFile(file);
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(out));
}

/// One data row, column for column with [catalogueSheetHeaders].
List<CellValue?> _cellsOf(CatalogueSheetRow row) => [
  // A blank ID cell (template rows) is what tells the import to CREATE.
  _text(row.productId == null ? '' : '${row.productId}'),
  _text(row.variantId == null ? '' : '${row.variantId}'),
  _text(row.unitId == null ? '' : '${row.unitId}'),
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
