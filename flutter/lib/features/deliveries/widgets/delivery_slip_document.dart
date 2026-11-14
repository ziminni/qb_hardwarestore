import 'dart:typed_data';

import 'package:client/core/format/format.dart';
import 'package:client/data/models/delivery.dart';
import 'package:client/data/models/pick_up.dart';
import 'package:client/features/labels/label_document.dart'
    show labelBoldFontAsset, labelFontAsset;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// The 80 mm roll the receipt already prints on, so a slip and a receipt can
/// come off the same counter printer.
final deliverySlipPageFormat = PdfPageFormat.roll80;

/// One carried line, already resolved to what the slip says.
class DeliverySlipLine {
  const DeliverySlipLine({
    required this.name,
    required this.quantity,
    required this.unit,
    this.pickUpAt,
    this.pickUp = const [],
  });

  final String name;
  final String quantity;
  final String unit;

  /// B4's "Stored at" (`Bodega`), or null when the server did not send one.
  final String? pickUpAt;

  /// Which shelves this line was picked from, in pick order (Phase 9, decision
  /// 21 §2). Empty on a slip whose sale predates Phase 9.
  final List<PickUpPart> pickUp;

  /// `2 BAG` — the selling quantity and its unit, as the driver counts it.
  String get quantityLine => '$quantity $unit'.trim();

  /// The line under the item, or null when there is nowhere in particular to
  /// pick it up. A split names both shelves; without one the Phase 5 caption
  /// stands; with neither there is NO line, rather than an invented place.
  String? get pickUpLine =>
      pickUpCaption(pickUp: pickUp, storedAtName: pickUpAt ?? '');
}

/// What the paper says, before any PDF layout.
///
/// Split out of [buildDeliverySlipPdf] so a test can read the content directly,
/// the same way `ReceiptContent` serves the receipt.
class DeliverySlipContent {
  DeliverySlipContent(Delivery delivery)
    : header = [
        'Delivery slip: ${delivery.documentNo}',
        delivery.sourceLabel,
        'Scheduled: ${formatDate(delivery.scheduledDate)}',
        'Contact: ${delivery.recipient}',
        if (delivery.contactPhone.isNotEmpty) 'Phone: ${delivery.contactPhone}',
        'Address: ${delivery.address}',
        'Status: ${delivery.status.label}',
      ],
      lines = [
        for (final item in delivery.items)
          DeliverySlipLine(
            name: item.name,
            quantity: formatQuantity(item.qty),
            unit: item.unit,
            pickUpAt: item.storedAtName,
            pickUp: item.pickUp,
          ),
      ],
      // A zero fee is not printed: the customer was charged for goods only, and
      // a "Delivery charge 0.00" line would read as a charge that was made.
      feeLine = delivery.fee > 0
          ? ('Delivery charge', formatPesoForPrint(delivery.fee))
          : null,
      failureReason = delivery.status == DeliveryStatus.failed
          ? delivery.failureReason
          : '';

  final List<String> header;
  final List<DeliverySlipLine> lines;

  /// The `Delivery charge` amount row, or null when the fee is 0.
  final (String, String)? feeLine;

  /// Why the trip failed, or empty. Only a FAILED slip carries one.
  final String failureReason;
}

/// Renders one delivery slip for the roll.
///
/// [font]/[bold] are parameters so a test can render with the PDF built-ins
/// while the app passes the bundled OpenSans (see
/// [buildDeliverySlipPdfWithOpenSans]).
Future<Uint8List> buildDeliverySlipPdf(
  Delivery delivery, {
  pw.Font? font,
  pw.Font? bold,
}) {
  final content = DeliverySlipContent(delivery);
  final body = pw.TextStyle(font: font ?? pw.Font.helvetica(), fontSize: 8);
  final strong = pw.TextStyle(
    font: bold ?? font ?? pw.Font.helveticaBold(),
    fontSize: 8,
  );
  final document = pw.Document();
  document.addPage(
    pw.Page(
      pageFormat: deliverySlipPageFormat,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Center(
            child: pw.Text(
              'QUEEN BUILDERS',
              style: strong.copyWith(fontSize: 11),
            ),
          ),
          pw.Center(child: pw.Text('Delivery slip', style: body)),
          pw.SizedBox(height: 6),
          for (final text in content.header) pw.Text(text, style: body),
          pw.Divider(thickness: 0.5),
          for (final line in content.lines)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(line.name, style: body),
                  pw.Text(line.quantityLine, style: body),
                  if (line.pickUpLine case final pickUp?)
                    pw.Text(pickUp, style: strong),
                ],
              ),
            ),
          pw.Divider(thickness: 0.5),
          if (content.feeLine case (final label, final amount))
            pw.Row(
              children: [
                pw.Expanded(child: pw.Text(label, style: strong)),
                pw.Text(amount, style: strong),
              ],
            ),
          if (content.failureReason.isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text('Failed: ${content.failureReason}', style: body),
          ],
          pw.SizedBox(height: 10),
          pw.Center(child: pw.Text('Thank you!', style: body)),
        ],
      ),
    ),
  );
  return document.save();
}

/// The app's build: the bundled OpenSans faces, loaded from assets.
Future<Uint8List> buildDeliverySlipPdfWithOpenSans(Delivery delivery) async {
  return buildDeliverySlipPdf(
    delivery,
    font: pw.Font.ttf(await rootBundle.load(labelFontAsset)),
    bold: pw.Font.ttf(await rootBundle.load(labelBoldFontAsset)),
  );
}
