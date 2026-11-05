import 'dart:typed_data';

import 'package:client/core/format/format.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/features/labels/label_document.dart'
    show labelBoldFontAsset, labelFontAsset;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// An 80 mm thermal roll, the width most counter receipt printers take. The
/// page grows with the lines, so a long basket is one strip, not many pages.
final receiptPageFormat = PdfPageFormat.roll80;

/// One label and amount at the foot of the receipt.
class ReceiptAmountRow {
  const ReceiptAmountRow(this.label, this.amount);
  final String label;
  final String amount;
}

/// What the paper says, before any PDF layout.
///
/// Split out of [buildReceiptPdf] so a test can read the content directly, the
/// same way `labelPages` serves the sticker document.
class ReceiptContent {
  ReceiptContent(PosReceipt receipt)
    : header = [
        'Receipt: ${receipt.officialReceiptNumber}',
        'Reference: ${receipt.reference}',
        formatDateTime(receipt.createdAt),
        'Payment: ${TenderMethod.labelFor(receipt.paymentMethod)}',
      ],
      lines = [
        for (final line in receipt.lines)
          (
            name: '${line.productName} · ${line.variantName}',
            detail:
                '${formatQuantity(line.quantity)} ${line.unit} × '
                '${formatPesoForPrint(line.unitPrice)}',
            total: formatPesoForPrint(line.total),
          ),
      ],
      amounts = [
        ReceiptAmountRow('Total', formatPesoForPrint(receipt.total)),
        ReceiptAmountRow('Paid', formatPesoForPrint(receipt.amountPaid)),
        // Same rule as the on-screen receipt: a shortfall is utang owed, not
        // negative change handed back.
        if (receipt.change < 0)
          ReceiptAmountRow(
            'Balance due (utang)',
            formatPesoForPrint(-receipt.change),
          )
        else
          ReceiptAmountRow('Change', formatPesoForPrint(receipt.change)),
      ];

  final List<String> header;
  final List<({String name, String detail, String total})> lines;
  final List<ReceiptAmountRow> amounts;
}

/// Renders one receipt for the roll.
///
/// [font]/[bold] are parameters so a test can render with the PDF built-ins
/// while the app passes the bundled OpenSans (see
/// [buildReceiptPdfWithOpenSans]).
Future<Uint8List> buildReceiptPdf(
  PosReceipt receipt, {
  pw.Font? font,
  pw.Font? bold,
}) {
  final content = ReceiptContent(receipt);
  final body = pw.TextStyle(font: font ?? pw.Font.helvetica(), fontSize: 8);
  final strong = pw.TextStyle(
    font: bold ?? font ?? pw.Font.helveticaBold(),
    fontSize: 8,
  );
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: receiptPageFormat,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text(
              'QUEEN BUILDERS',
              style: strong.copyWith(fontSize: 11),
            ),
          ),
          pw.Center(child: pw.Text('Hardware store', style: body)),
          pw.SizedBox(height: 6),
          for (final text in content.header) pw.Text(text, style: body),
          pw.Divider(thickness: 0.5),
          for (final line in content.lines)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(line.name, style: body),
                        pw.Text(line.detail, style: body),
                      ],
                    ),
                  ),
                  pw.Text(line.total, style: body),
                ],
              ),
            ),
          pw.Divider(thickness: 0.5),
          for (final row in content.amounts)
            pw.Row(
              children: [
                pw.Expanded(child: pw.Text(row.label, style: strong)),
                pw.Text(row.amount, style: strong),
              ],
            ),
          pw.SizedBox(height: 10),
          pw.Center(child: pw.Text('Thank you!', style: body)),
        ],
      ),
    ),
  );
  return document.save();
}

/// The app's build: the bundled OpenSans faces, loaded from assets.
Future<Uint8List> buildReceiptPdfWithOpenSans(PosReceipt receipt) async {
  return buildReceiptPdf(
    receipt,
    font: pw.Font.ttf(await rootBundle.load(labelFontAsset)),
    bold: pw.Font.ttf(await rootBundle.load(labelBoldFontAsset)),
  );
}
