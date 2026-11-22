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

/// The table's column headings, in CSV/reference order.
const barcodeListColumns = <String>[
  'Product',
  'Variant',
  'Unit',
  'Price',
  'Code',
  'Barcode',
];

/// Booklet layout geometry for A4 counter scan sheets: 2 columns × 5 rows = 10
/// spaced cards per page so a handheld scanner never accidentally reads an
/// adjacent item.
const barcodeBookletColumns = 2;
const barcodeBookletRowsPerPage = 5;
const barcodeBookletItemsPerPage =
    barcodeBookletColumns * barcodeBookletRowsPerPage;

/// Splits [rows] into fixed-size booklet pages of [barcodeBookletItemsPerPage].
///
/// An empty list still yields one empty page so the PDF always prints the
/// header, filter summary, and empty-state note.
List<List<BarcodeListRow>> barcodeBookletPages(List<BarcodeListRow> rows) {
  if (rows.isEmpty) return const [[]];
  return [
    for (var start = 0; start < rows.length; start += barcodeBookletItemsPerPage)
      rows.sublist(
        start,
        start + barcodeBookletItemsPerPage > rows.length
            ? rows.length
            : start + barcodeBookletItemsPerPage,
      ),
  ];
}

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

/// Renders the masterlist as a printable A4 counter scan booklet: 2 columns ×
/// 5 spaced cards per page, generous white quiet zones around each barcode,
/// a wider left margin for stapling/punch-binding, and a header + page number
/// on every page.
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
  final pages = barcodeBookletPages(data.rows);
  final totalPages = pages.length;

  for (var pageIndex = 0; pageIndex < totalPages; pageIndex++) {
    final pageRows = pages[pageIndex];
    final pageNumber = pageIndex + 1;
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        // Extra left gutter (18 mm) leaves room to staple or ring-bind sheets
        // into a flip-through counter booklet without clipping cards.
        margin: const pw.EdgeInsets.fromLTRB(
          18 * PdfPageFormat.mm,
          12 * PdfPageFormat.mm,
          12 * PdfPageFormat.mm,
          12 * PdfPageFormat.mm,
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            _bookletHeader(heading, body, strong),
            pw.SizedBox(height: 5 * PdfPageFormat.mm),
            pw.Expanded(
              child: pageRows.isEmpty
                  ? pw.Align(
                      alignment: pw.Alignment.topLeft,
                      child: pw.Text(
                        'No codes match these filters.',
                        style: pw.TextStyle(font: body, fontSize: 10),
                      ),
                    )
                  : _bookletGrid(pageRows, body, strong),
            ),
            _bookletFooter(pageNumber, totalPages, body),
          ],
        ),
      ),
    );
  }
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

pw.Widget _bookletHeader(List<String> heading, pw.Font body, pw.Font strong) {
  return pw.Container(
    padding: const pw.EdgeInsets.only(bottom: 2.5 * PdfPageFormat.mm),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColors.grey400, width: 0.6),
      ),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final (index, line) in heading.indexed)
          pw.Padding(
            padding: pw.EdgeInsets.only(bottom: index == 0 ? 1.5 : 0.5),
            child: pw.Text(
              line,
              style: pw.TextStyle(
                font: index == 0 ? strong : body,
                fontSize: index == 0 ? 13 : 8,
                color: index == 0 ? PdfColors.black : PdfColors.grey700,
              ),
            ),
          ),
      ],
    ),
  );
}

pw.Widget _bookletFooter(int pageNumber, int totalPages, pw.Font body) {
  return pw.Container(
    margin: const pw.EdgeInsets.only(top: 3 * PdfPageFormat.mm),
    padding: const pw.EdgeInsets.only(top: 1.5 * PdfPageFormat.mm),
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      ),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Barcode scan booklet',
          style: pw.TextStyle(
            font: body,
            fontSize: 7.5,
            color: PdfColors.grey600,
          ),
        ),
        pw.Text(
          barcodeListPageLabel(pageNumber, totalPages),
          style: pw.TextStyle(
            font: body,
            fontSize: 8,
            color: PdfColors.grey700,
          ),
        ),
      ],
    ),
  );
}

/// 2-column × up-to-5-row booklet card grid with generous horizontal (10 mm)
/// and vertical (8 mm) gaps between cards so scanners stay isolated on one code.
pw.Widget _bookletGrid(
  List<BarcodeListRow> pageRows,
  pw.Font body,
  pw.Font strong,
) {
  final rowPairs = <pw.Widget>[];
  for (var i = 0; i < pageRows.length; i += barcodeBookletColumns) {
    final left = pageRows[i];
    final right = i + 1 < pageRows.length ? pageRows[i + 1] : null;
    if (rowPairs.isNotEmpty) {
      rowPairs.add(pw.SizedBox(height: 8 * PdfPageFormat.mm));
    }
    rowPairs.add(
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(child: _bookletCard(left, body, strong)),
          pw.SizedBox(width: 10 * PdfPageFormat.mm),
          pw.Expanded(
            child: right != null
                ? _bookletCard(right, body, strong)
                : pw.SizedBox(),
          ),
        ],
      ),
    );
  }
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: rowPairs,
  );
}

/// One booklet card (85 mm × 40 mm): tinted item header on top, wide white
/// quiet-zone barcode pad and human-readable code underneath.
pw.Widget _bookletCard(BarcodeListRow row, pw.Font body, pw.Font strong) {
  final variantLabel = row.variantName.trim();
  return pw.Container(
    height: 40 * PdfPageFormat.mm,
    decoration: pw.BoxDecoration(
      color: PdfColors.white,
      border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(
          padding: const pw.EdgeInsets.fromLTRB(8, 5, 8, 4.5),
          decoration: const pw.BoxDecoration(
            color: PdfColors.grey100,
            borderRadius: pw.BorderRadius.only(
              topLeft: pw.Radius.circular(3.4),
              topRight: pw.Radius.circular(3.4),
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      row.productName,
                      style: pw.TextStyle(
                        font: strong,
                        fontSize: 8.5,
                        color: PdfColors.black,
                      ),
                      maxLines: 2,
                      overflow: pw.TextOverflow.clip,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Text(
                    // The bundled fonts have no ₱ glyph (see formatPesoForPrint),
                    // so the paper says PHP the way a Philippine receipt does.
                    formatPesoForPrint(row.price),
                    style: pw.TextStyle(
                      font: strong,
                      fontSize: 8.5,
                      color: PdfColors.grey900,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
              pw.SizedBox(height: 2),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      variantLabel.isEmpty ? 'Standard' : variantLabel,
                      style: pw.TextStyle(
                        font: body,
                        fontSize: 7.5,
                        color: PdfColors.grey700,
                      ),
                      maxLines: 1,
                      overflow: pw.TextOverflow.clip,
                    ),
                  ),
                  pw.SizedBox(width: 6),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 4.5,
                      vertical: 1,
                    ),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.white,
                      border: pw.Border.all(
                        color: PdfColors.grey400,
                        width: 0.4,
                      ),
                      borderRadius: const pw.BorderRadius.all(
                        pw.Radius.circular(2.5),
                      ),
                    ),
                    child: pw.Text(
                      row.unitCode,
                      style: pw.TextStyle(
                        font: strong,
                        fontSize: 6.8,
                        color: PdfColors.grey800,
                      ),
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        pw.Container(height: 0.4, color: PdfColors.grey300),
        pw.Expanded(
          child: pw.Padding(
            padding: const pw.EdgeInsets.symmetric(
              horizontal: 6 * PdfPageFormat.mm,
              vertical: 2 * PdfPageFormat.mm,
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                _barcode(row),
                pw.SizedBox(height: 3),
                pw.Text(
                  row.code,
                  style: pw.TextStyle(
                    font: strong,
                    fontSize: 8,
                    letterSpacing: 0.6,
                    color: PdfColors.grey900,
                  ),
                  maxLines: 1,
                  overflow: pw.TextOverflow.clip,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/// The scannable bars of a booklet card: EAN when the code verifies, Code 128
/// otherwise. Sized wide (56 mm × 12.5 mm) with surrounding white quiet zone
/// for quick, mis-scan-free counter scanning.
pw.Widget _barcode(BarcodeListRow row) {
  final barcode = switch (row.symbology) {
    BarcodeSymbology.ean13 => pw.Barcode.ean13(),
    BarcodeSymbology.ean8 => pw.Barcode.ean8(),
    BarcodeSymbology.code128 => pw.Barcode.code128(),
  };
  return pw.BarcodeWidget(
    barcode: barcode,
    data: row.code,
    drawText: false,
    width: 56 * PdfPageFormat.mm,
    height: 12.5 * PdfPageFormat.mm,
  );
}
