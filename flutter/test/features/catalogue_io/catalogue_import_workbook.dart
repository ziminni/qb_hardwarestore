// The import tests' workbook builder: a real .xlsx built cell by cell, the way
// Excel hands one back, so the parser is read by its own bytes and not a stub.

import 'dart:typed_data';

import 'package:client/features/catalogue_io/catalogue_sheet.dart';
import 'package:client/features/catalogue_io/catalogue_xlsx.dart';
import 'package:excel_community/excel_community.dart';

/// A workbook built cell by cell, the way Excel hands it back.
Uint8List workbook({
  List<String> headers = catalogueSheetHeaders,
  List<List<Object?>> rows = const [],
  String sheetName = catalogueSheetName,
}) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', sheetName);
  final sheet = excel[sheetName];
  sheet.appendRow([for (final header in headers) TextCellValue(header)]);
  for (final row in rows) {
    sheet.appendRow([
      for (final cell in row)
        switch (cell) {
          null => null,
          final int value => IntCellValue(value),
          final double value => DoubleCellValue(value),
          final bool value => BoolCellValue(value),
          final String value => TextCellValue(value),
          _ => TextCellValue('$cell'),
        },
    ]);
  }
  final bytes = excel.encode();
  if (bytes == null) throw StateError('test workbook did not encode');
  return Uint8List.fromList(bytes);
}

/// One full row of cells, in sheet order, overridable per column.
List<Object?> rowCells({
  String productId = '6',
  String variantId = '8',
  String unitId = '11',
  String category = 'Electrical',
  String brand = 'Omni',
  String productName = 'Circuit Breaker',
  String variant = '20A 1-pole',
  String unitCode = 'PC',
  Object? unitsPerBase = 1,
  Object? price = 315,
  String barcode = 'QB000013-0',
  Object? lowStockThreshold = 5,
  String storedAt = 'Bodega',
  Object? active = 'Yes',
}) => [
  productId,
  variantId,
  unitId,
  category,
  brand,
  productName,
  variant,
  unitCode,
  unitsPerBase,
  price,
  barcode,
  lowStockThreshold,
  storedAt,
  active,
];

/// A row a clerk emptied (but did not delete), which the parser skips.
List<Object?> emptiedRow() =>
    List<Object?>.filled(catalogueSheetHeaders.length, '');
