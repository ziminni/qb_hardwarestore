import 'dart:convert';
import 'dart:typed_data';

import 'package:client/features/labels/barcode_list_document.dart';

/// The barcode list as CSV (Phase 4 Task F2).
///
/// Two details make the difference between a file a storekeeper can open in Excel
/// and a mess: RFC 4180 quoting (a comma, quote or newline inside a name would
/// otherwise shift every column) and a UTF-8 BOM (without it Excel reads the file
/// as the system code page and mangles every peso sign).

/// The column headings, in the same order as the PDF table.
const barcodeListCsvHeaders = <String>[
  'Product',
  'Variant',
  'Unit',
  'Price',
  'Code',
];

/// The file as text: CRLF between records, as RFC 4180 asks.
///
/// The price is a PLAIN number (`315.00`) rather than `formatPeso`, because the
/// column's whole use is sorting and totalling in a spreadsheet; the ₱ sign lives
/// on paper, in the PDF.
String barcodeListCsv(List<BarcodeListRow> rows) {
  final buffer = StringBuffer()
    ..write(barcodeListCsvHeaders.map(_field).join(','))
    ..write('\r\n');
  for (final row in rows) {
    buffer
      ..write(
        [
          _textField(row.productName),
          _textField(row.variantName),
          _textField(row.unitCode),
          row.price.toStringAsFixed(2),
          _textField(row.code),
        ].join(','),
      )
      ..write('\r\n');
  }
  return buffer.toString();
}

/// The file as bytes, ready for a download or a save dialog.
///
/// The BOM (EF BB BF) is what tells Excel the file is UTF-8.
Uint8List barcodeListCsvBytes(List<BarcodeListRow> rows) => Uint8List.fromList([
  0xEF,
  0xBB,
  0xBF,
  ...utf8.encode(barcodeListCsv(rows)),
]);

/// One CSV field: quoted only when it has to be, with quotes doubled inside.
String _field(String value) {
  final needsQuotes = value.contains(RegExp(r'[",\r\n]'));
  if (!needsQuotes) return value;
  return '"${value.replaceAll('"', '""')}"';
}

/// A user-supplied text field, safe to open in a spreadsheet.
///
/// A name starting `=`, `+`, `-`, `@`, TAB or CR is a formula to Excel and
/// LibreOffice and would run on open (OWASP CSV injection), so it gets a leading
/// apostrophe — Excel shows the cell as text and hides the mark. The price is
/// written plain instead, because totals and sorting need a number.
String _textField(String value) => _field(
  value.isNotEmpty && '=+-@\t\r'.contains(value[0]) ? "'$value" : value,
);
