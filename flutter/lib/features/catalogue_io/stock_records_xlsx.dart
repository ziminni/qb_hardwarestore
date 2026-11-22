import 'dart:typed_data';

import 'package:client/core/format/spreadsheet_text.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:excel_community/excel_community.dart';

/// Headings for the live Stock Records workbook exported by Stock Managers.
const stockRecordsSheetHeaders = <String>[
  'Product',
  'Variant',
  'SKU',
  'Category',
  'Brand',
  'Stored at',
  'Unit',
  'On hand',
  'Low-stock threshold',
  'Status',
  'Unit cost',
  'Stock value',
  'Selling price',
  'Barcode',
];

const stockRecordsSheetName = 'Stock Records';

class StockRecordSheetRow {
  const StockRecordSheetRow({
    required this.productName,
    required this.variantName,
    required this.sku,
    required this.category,
    required this.brand,
    required this.storedAt,
    required this.unitCode,
    required this.onHand,
    required this.lowStockThreshold,
    required this.statusLabel,
    required this.unitCost,
    required this.stockValue,
    required this.sellingPrice,
    required this.barcode,
  });

  final String productName;
  final String variantName;
  final String sku;
  final String category;
  final String brand;
  final String storedAt;
  final String unitCode;
  final double onHand;
  final double lowStockThreshold;
  final String statusLabel;
  final double unitCost;
  final double stockValue;
  final double sellingPrice;
  final String barcode;
}

/// Builds one spreadsheet row per product variant from live stock records.
List<StockRecordSheetRow> stockRecordSheetRows({
  required Iterable<({Product product, ProductVariant variant})> records,
  required double Function(int variantId) stockOnHandFor,
  required double? Function(int variantId) costFor,
  required InventoryStockStatus Function(int variantId) statusForVariant,
  List<VariantUom> Function(ProductVariant variant)? unitsOf,
}) {
  final rows = <StockRecordSheetRow>[];
  for (final record in records) {
    final product = record.product;
    final variant = record.variant;
    final units = unitsOf?.call(variant) ?? variant.sellingUoms;
    VariantUom? baseUnit;
    for (final unit in units) {
      if (unit.uomId == variant.baseUomId && unit.conversionFactor == 1) {
        baseUnit = unit;
        break;
      }
    }
    baseUnit ??= units.firstOrNull;
    final onHand = stockOnHandFor(variant.id);
    final cost = costFor(variant.id) ?? 0;
    final status = statusForVariant(variant.id);
    rows.add(
      StockRecordSheetRow(
        productName: product.baseName,
        variantName: variant.variantName,
        sku: variant.sku,
        category: product.categoryName,
        brand: product.brandName,
        storedAt: product.storedAtName,
        unitCode: variant.baseUomCode,
        onHand: onHand,
        lowStockThreshold: variant.minStockThreshold,
        statusLabel: status.label,
        unitCost: cost,
        stockValue: double.parse((onHand * cost).toStringAsFixed(2)),
        sellingPrice: baseUnit?.defaultSellingPrice ?? 0,
        barcode: baseUnit?.barcodeQr ?? variant.barcode,
      ),
    );
  }
  return rows;
}

/// Encodes [rows] into an `.xlsx` workbook for Excel / LibreOffice Calc.
Uint8List stockRecordsXlsxBytes(List<StockRecordSheetRow> rows) {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', stockRecordsSheetName);
  final sheet = excel[stockRecordsSheetName];

  const widths = <double>[
    28, 18, 16, 18, 16, 14, 10, 12, 18, 14, 12, 14, 14, 18,
  ];
  final headerStyle = CellStyle(
    bold: true,
    backgroundColorHex: ExcelColor.fromHexString('#E1C684'),
    textWrapping: TextWrapping.WrapText,
  );

  sheet.appendRow([for (final h in stockRecordsSheetHeaders) _text(h)]);
  for (var col = 0; col < stockRecordsSheetHeaders.length; col++) {
    sheet.setColumnWidth(col, widths[col]);
    sheet
        .cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0))
        .cellStyle = headerStyle;
  }

  for (final row in rows) {
    sheet.appendRow([
      _text(row.productName),
      _text(row.variantName),
      _text(row.sku),
      _text(row.category),
      _text(row.brand),
      _text(row.storedAt),
      _text(row.unitCode),
      _number(row.onHand),
      _number(row.lowStockThreshold),
      _text(row.statusLabel),
      _number(row.unitCost),
      _number(row.stockValue),
      _number(row.sellingPrice),
      _text(row.barcode),
    ]);
  }

  final bytes = excel.encode();
  if (bytes == null) {
    throw StateError('Could not encode the stock records workbook.');
  }
  return Uint8List.fromList(bytes);
}

CellValue _text(String value) => TextCellValue(spreadsheetSafeText(value));

CellValue _number(double value) {
  final isWhole = value == value.roundToDouble() && value.abs() < 1e15;
  return isWhole ? IntCellValue(value.toInt()) : DoubleCellValue(value);
}
