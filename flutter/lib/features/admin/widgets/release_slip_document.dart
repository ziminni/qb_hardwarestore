import 'dart:typed_data';

import 'package:client/core/format/format.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/features/labels/label_document.dart'
    show labelBoldFontAsset, labelFontAsset;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// The same 80 mm roll as the sales receipt, so the counter needs one printer.
final releaseSlipPageFormat = PdfPageFormat.roll80;

/// What the slip says, before any PDF layout.
///
/// [qrData] is the token and nothing else: a 2D scanner at Release materials
/// types exactly what the QR holds and presses Enter, so any prefix would land
/// in the token field and fail verification.
class ReleaseSlipContent {
  ReleaseSlipContent(Requisition requisition)
    : assert(requisition.token != null, 'only an approved requisition has a slip'),
      reqNumber = requisition.reqNumber,
      details = [
        'Project: ${requisition.projectName}',
        if (requisition.projectCustomerName.isNotEmpty)
          'Customer: ${requisition.projectCustomerName}',
        'Requested by: ${requisition.requestedByName}',
      ],
      lines = [
        for (final item in requisition.items)
          (name: item.variantName, quantity: formatQuantity(item.quantity)),
      ],
      qrData = requisition.token!;

  final String reqNumber;
  final List<String> details;
  final List<({String name, String quantity})> lines;
  final String qrData;
}

/// Renders the slip the foreman carries to the store.
///
/// [font]/[bold] are parameters so a test can render with the PDF built-ins
/// while the app passes the bundled OpenSans.
Future<Uint8List> buildReleaseSlipPdf(
  Requisition requisition, {
  pw.Font? font,
  pw.Font? bold,
}) {
  final content = ReleaseSlipContent(requisition);
  final body = pw.TextStyle(font: font ?? pw.Font.helvetica(), fontSize: 8);
  final strong = pw.TextStyle(
    font: bold ?? font ?? pw.Font.helveticaBold(),
    fontSize: 8,
  );
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: releaseSlipPageFormat,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text(
              'MATERIAL RELEASE SLIP',
              style: strong.copyWith(fontSize: 11),
            ),
          ),
          pw.Center(child: pw.Text(content.reqNumber, style: strong)),
          pw.SizedBox(height: 6),
          for (final text in content.details) pw.Text(text, style: body),
          pw.Divider(thickness: 0.5),
          for (final line in content.lines)
            pw.Row(
              children: [
                pw.Expanded(child: pw.Text(line.name, style: body)),
                pw.Text(line.quantity, style: body),
              ],
            ),
          pw.Divider(thickness: 0.5),
          pw.Center(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.qrCode(),
              data: content.qrData,
              width: 40 * PdfPageFormat.mm,
              height: 40 * PdfPageFormat.mm,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(content.qrData, style: body.copyWith(fontSize: 7)),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Present this slip at the store counter. Whoever holds it can '
            'release these goods, and it works once.',
            style: body.copyWith(fontSize: 7),
            textAlign: pw.TextAlign.center,
          ),
        ],
      ),
    ),
  );
  return document.save();
}

/// Hands a release slip to the platform; an interface so tests can fake it.
abstract class ReleaseSlipPrinter {
  Future<void> print(Requisition requisition);
}

/// The real one: the OS print dialog, like the receipt and the labels.
class PdfReleaseSlipPrinter implements ReleaseSlipPrinter {
  const PdfReleaseSlipPrinter();

  @override
  Future<void> print(Requisition requisition) async {
    final font = pw.Font.ttf(await rootBundle.load(labelFontAsset));
    final bold = pw.Font.ttf(await rootBundle.load(labelBoldFontAsset));
    await Printing.layoutPdf(
      name: requisition.reqNumber,
      format: releaseSlipPageFormat,
      onLayout: (_) => buildReleaseSlipPdf(requisition, font: font, bold: bold),
    );
  }
}

/// Prints the slip and says so if the printer refused.
Future<void> printReleaseSlip(
  BuildContext context,
  Requisition requisition, {
  ReleaseSlipPrinter? printer,
}) async {
  try {
    await (printer ?? const PdfReleaseSlipPrinter()).print(requisition);
  } catch (error) {
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text('Could not print the slip: $error')),
    );
  }
}
