import 'dart:typed_data';

import 'package:client/core/format/format.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/labels/label_document.dart'
    show labelBoldFontAsset, labelFontAsset;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The barcode masterlist (Phase 4 Task F2, panel comment #5).
///
/// One row per SELLING UNIT, because the code a scanner reads belongs to the unit
/// (`VariantUom.barcodeQr`), not to the product: the same breaker in PC and in BOX
/// is two codes. The row is what the PDF table and the CSV row are built from, so a
/// test can check the payload without parsing PDF bytes or reading pixels.
enum BarcodeSymbology {
  /// A factory code: 13 digits with a valid modulo-10 check digit.
  ean13,

  /// A factory code: 8 digits with a valid modulo-10 check digit.
  ean8,

  /// Everything else, including the server's own `QB…` codes.
  code128,
}

/// Which symbology a code can actually be printed as.
///
/// `pdf`'s EAN encoder REFUSES a wrong length or check digit, so guessing from the
/// digit count alone would throw on a mis-keyed code and lose the whole page. Only
/// a code whose check digit verifies becomes an EAN; the rest fall back to Code 128,
/// which encodes any text.
BarcodeSymbology barcodeSymbologyFor(String code) {
  final normalised = VariantUom.normalise(code);
  if (normalised.length == 13 && _eanCheckDigitMatches(normalised)) {
    return BarcodeSymbology.ean13;
  }
  if (normalised.length == 8 && _eanCheckDigitMatches(normalised)) {
    return BarcodeSymbology.ean8;
  }
  return BarcodeSymbology.code128;
}

/// True when the last digit is the EAN modulo-10 check digit of the digits before
/// it. Weights alternate 3, 1 from the digit left of the check digit.
bool _eanCheckDigitMatches(String digits) {
  if (!RegExp(r'^\d+$').hasMatch(digits)) return false;
  var sum = 0;
  var weight = 3;
  for (var index = digits.length - 2; index >= 0; index--) {
    sum += int.parse(digits[index]) * weight;
    weight = weight == 3 ? 1 : 3;
  }
  final expected = (10 - sum % 10) % 10;
  return expected == int.parse(digits[digits.length - 1]);
}

/// One line of the masterlist: what to scan, and what it sells as.
class BarcodeListRow {
  const BarcodeListRow({
    required this.productName,
    required this.variantName,
    required this.unitCode,
    required this.price,
    required this.code,
  });

  final String productName;
  final String variantName;
  final String unitCode;
  final double price;
  final String code;

  BarcodeSymbology get symbology => barcodeSymbologyFor(code);
}

/// Everything the document and the CSV need: the rows, plus what was filtered.
///
/// Carried together so the printed sheet says what it is ("Active only", which
/// category) instead of looking like the whole catalogue.
class BarcodeListData {
  const BarcodeListData({
    required this.rows,
    required this.generatedAt,
    required this.categoryLabel,
    required this.activeOnly,
  });

  final List<BarcodeListRow> rows;
  final DateTime generatedAt;
  final String categoryLabel;
  final bool activeOnly;
}

/// The table's column headings, in PDF and CSV order.
const barcodeListColumns = <String>[
  'Product',
  'Variant',
  'Unit',
  'Price',
  'Code',
  'Barcode',
];

/// The rows of ONE product, one per selling unit.
///
/// [unitsOf] lets a caller pass the selling units the store reloaded (the nested
/// `selling_uoms` on the products endpoint can be older than the `/variant-uoms/`
/// rows a code edit returns). A unit without a code is skipped: there is nothing to
/// scan, and an empty barcode box on a masterlist is a trap.
List<BarcodeListRow> barcodeListRowsForProduct(
  Product product, {
  List<VariantUom> Function(ProductVariant variant)? unitsOf,
}) {
  final rows = <BarcodeListRow>[];
  for (final variant in product.variants) {
    final units = unitsOf?.call(variant) ?? variant.sellingUoms;
    for (final unit in units) {
      final code = VariantUom.normalise(unit.barcodeQr);
      if (code.isEmpty) continue;
      rows.add(
        BarcodeListRow(
          productName: product.baseName,
          variantName: variant.variantName,
          unitCode: unit.uomCode,
          price: unit.defaultSellingPrice,
          code: code,
        ),
      );
    }
  }
  return rows;
}

/// The whole list, in catalogue order.
List<BarcodeListRow> barcodeListRows(
  Iterable<Product> products, {
  List<VariantUom> Function(ProductVariant variant)? unitsOf,
}) => [
  for (final product in products)
    ...barcodeListRowsForProduct(product, unitsOf: unitsOf),
];

/// The heading block printed at the top of every page.
///
/// A list of lines rather than a widget so a test can assert the generated date,
/// the filters and the count without reading PDF content streams (which are
/// compressed).
List<String> barcodeListHeaderLines(BarcodeListData data) => [
  'Barcode list',
  'Generated ${formatDateTime(data.generatedAt)}',
  '${data.categoryLabel} · '
      '${data.activeOnly ? 'Active only' : 'Active and archived'} · '
      '${formatCount(data.rows.length)} '
      '${data.rows.length == 1 ? 'code' : 'codes'}',
];

/// `Page 2 of 5`, for the footer of every page.
String barcodeListPageLabel(int page, int total) => 'Page $page of $total';

/// Renders the masterlist as an A4 PDF: a repeating table header, a scannable
/// barcode per row and a page number on every page.
///
/// [font]/[bold] are parameters so a test can render with the PDF built-ins while
/// the app passes the bundled OpenSans (see [buildBarcodeListPdfWithOpenSans]).
Future<Uint8List> buildBarcodeListPdf(
  BarcodeListData data, {
  pw.Font? font,
  pw.Font? bold,
}) {
  final document = pw.Document();
  final body = font ?? pw.Font.helvetica();
  final strong = bold ?? font ?? pw.Font.helveticaBold();
  final heading = barcodeListHeaderLines(data);

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(
        12 * PdfPageFormat.mm,
        12 * PdfPageFormat.mm,
        12 * PdfPageFormat.mm,
        14 * PdfPageFormat.mm,
      ),
      header: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            for (final (index, line) in heading.indexed)
              pw.Text(
                line,
                style: pw.TextStyle(
                  font: index == 0 ? strong : body,
                  fontSize: index == 0 ? 14 : 8,
                ),
              ),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          // `pagesCount` is only known once layout has run, which is why the
          // "of y" half cannot be written by hand.
          barcodeListPageLabel(context.pageNumber, context.pagesCount),
          style: pw.TextStyle(font: body, fontSize: 8),
        ),
      ),
      build: (context) => [
        if (data.rows.isEmpty)
          pw.Text(
            'No codes match these filters.',
            style: pw.TextStyle(font: body, fontSize: 10),
          )
        else
          pw.TableHelper.fromTextArray(
            headers: barcodeListColumns,
            data: [
              for (final row in data.rows)
                [
                  row.productName,
                  row.variantName,
                  row.unitCode,
                  // The bundled fonts have no ₱ glyph (see formatPesoForPrint), so
                  // the paper says PHP the way a Philippine receipt does.
                  formatPesoForPrint(row.price),
                  row.code,
                  _barcode(row, strong),
                ],
            ],
            cellStyle: pw.TextStyle(font: body, fontSize: 8),
            headerStyle: pw.TextStyle(font: strong, fontSize: 8),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey300),
            headerAlignment: pw.Alignment.centerLeft,
            cellAlignments: const {
              3: pw.Alignment.centerRight,
              5: pw.Alignment.center,
            },
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(1),
              3: pw.FlexColumnWidth(1.6),
              4: pw.FlexColumnWidth(2.2),
              5: pw.FlexColumnWidth(2.8),
            },
            border: pw.TableBorder.all(width: 0.3, color: PdfColors.grey600),
          ),
      ],
    ),
  );
  return document.save();
}

/// The app's build: the bundled OpenSans faces, loaded from assets.
Future<Uint8List> buildBarcodeListPdfWithOpenSans(BarcodeListData data) async {
  return buildBarcodeListPdf(
    data,
    font: pw.Font.ttf(await rootBundle.load(labelFontAsset)),
    bold: pw.Font.ttf(await rootBundle.load(labelBoldFontAsset)),
  );
}

/// The scannable half of a row: EAN when the code verifies, Code 128 otherwise.
pw.Widget _barcode(BarcodeListRow row, pw.Font font) {
  final barcode = switch (row.symbology) {
    BarcodeSymbology.ean13 => pw.Barcode.ean13(),
    BarcodeSymbology.ean8 => pw.Barcode.ean8(),
    BarcodeSymbology.code128 => pw.Barcode.code128(),
  };
  return pw.BarcodeWidget(
    barcode: barcode,
    data: row.code,
    drawText: false,
    width: 34 * PdfPageFormat.mm,
    height: 9 * PdfPageFormat.mm,
  );
}
