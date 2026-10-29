import 'dart:typed_data';

import 'package:client/data/models/variant_uom.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The bundled font for label text.
///
/// Helvetica (the PDF default) has no glyphs beyond Latin-1, and a product name is
/// whatever the shop typed. Task 0's ruling: load OpenSans from assets instead.
const labelFontAsset = 'assets/fonts/OpenSans-Regular.ttf';
const labelBoldFontAsset = 'assets/fonts/OpenSans-Bold.ttf';

/// The hard ceiling on one unit's copies (decision 14).
///
/// A mis-keyed 10 000 is a whole roll of labels and a jammed printer, so the copies
/// field in the label dialog and the Receiving pre-fill both stop here.
const labelMaxCopies = 200;

/// One sticker: 50 × 30 mm with 2 mm margins (decision 14).
///
/// shortcut: one roll size; add a size picker if the store switches rolls.
final labelPageFormat = PdfPageFormat(
  50 * PdfPageFormat.mm,
  30 * PdfPageFormat.mm,
  marginAll: 2 * PdfPageFormat.mm,
);

/// One selling unit the user asked to label, and how many copies.
class LabelRequest {
  const LabelRequest({
    required this.code,
    required this.productName,
    required this.variantName,
    required this.unitName,
    this.copies = 1,
  });

  final String code;
  final String productName;
  final String variantName;
  final String unitName;
  final int copies;
}

/// The content of ONE sticker, after filtering and expansion.
///
/// Split out of [buildLabelPdf] on purpose: a test can then assert exactly what
/// lands on each page without parsing PDF bytes or reading pixels.
class LabelPageData {
  const LabelPageData({
    required this.code,
    required this.productName,
    required this.variantName,
    required this.unitName,
  });

  final String code;
  final String productName;
  final String variantName;
  final String unitName;
}

/// What actually gets printed: one entry per sticker, in request order.
///
/// Only `QB…` codes become stickers — a unit with a factory EAN already has a
/// label from its manufacturer, so it is skipped rather than duplicated (decision
/// 14). The caller filters too; this is the guard that makes the document correct
/// on its own.
List<LabelPageData> labelPages(Iterable<LabelRequest> requests) {
  final pages = <LabelPageData>[];
  for (final request in requests) {
    final code = VariantUom.normalise(request.code);
    if (!code.startsWith('QB')) continue;
    for (var copy = 0; copy < request.copies; copy++) {
      pages.add(
        LabelPageData(
          code: code,
          productName: request.productName,
          variantName: request.variantName,
          unitName: request.unitName,
        ),
      );
    }
  }
  return pages;
}

/// Renders the stickers as one PDF page per copy.
///
/// [font]/[bold] are parameters so a test can render with the PDF built-ins while
/// the app passes the bundled OpenSans (see [buildLabelPdfWithOpenSans]).
Future<Uint8List> buildLabelPdf(
  List<LabelRequest> requests, {
  pw.Font? font,
  pw.Font? bold,
}) {
  final document = pw.Document();
  final body = font ?? pw.Font.helvetica();
  final strong = bold ?? font ?? pw.Font.helveticaBold();
  for (final page in labelPages(requests)) {
    document.addPage(
      pw.Page(
        pageFormat: labelPageFormat,
        build: (_) => _sticker(page, body, strong),
      ),
    );
  }
  return document.save();
}

/// The app's build: the bundled OpenSans faces, loaded from assets.
Future<Uint8List> buildLabelPdfWithOpenSans(List<LabelRequest> requests) async {
  return buildLabelPdf(
    requests,
    font: pw.Font.ttf(await rootBundle.load(labelFontAsset)),
    bold: pw.Font.ttf(await rootBundle.load(labelBoldFontAsset)),
  );
}

/// Code 128 bars, the code in full (never truncated), then what the unit is.
///
/// No price: the server's price is the authority and a printed one goes stale
/// (decision 14).
pw.Widget _sticker(LabelPageData page, pw.Font font, pw.Font bold) {
  final width = labelPageFormat.availableWidth;
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.BarcodeWidget(
        barcode: pw.Barcode.code128(),
        data: page.code,
        drawText: false,
        width: width,
        height: 12 * PdfPageFormat.mm,
      ),
      pw.Text(
        page.code,
        style: pw.TextStyle(font: bold, fontSize: 8),
        maxLines: 1,
      ),
      pw.SizedBox(
        width: width,
        child: pw.Text(
          '${page.productName} · ${page.variantName}',
          style: pw.TextStyle(font: font, fontSize: 6),
          maxLines: 1,
          textAlign: pw.TextAlign.center,
          overflow: pw.TextOverflow.clip,
        ),
      ),
      pw.Text(
        page.unitName,
        style: pw.TextStyle(font: font, fontSize: 6),
        maxLines: 1,
      ),
    ],
  );
}
