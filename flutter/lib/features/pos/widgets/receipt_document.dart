import 'dart:typed_data';

import 'package:client/core/format/format.dart';
import 'package:client/core/printing/escpos.dart';
import 'package:client/data/models/pick_up.dart';
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

/// `Discount (senior)` for a reasoned discount, plain `Discount` when the reason is
/// empty (a legacy row). The reason is what the manager wrote, so it is shown, not
/// summarised away.
String receiptDiscountLabel(String reason) {
  final trimmed = reason.trim();
  return trimmed.isEmpty ? 'Discount' : 'Discount ($trimmed)';
}

/// `VAT (12%)` from the store's rate, or plain `VAT` when the rate is unknown.
///
/// No em dash and no locale: the receipt owner reads one rate on every sale.
String receiptVatLabel(double rate) {
  if (rate <= 0) return 'VAT';
  final text = rate.toStringAsFixed(2);
  final trimmed = text.endsWith('.00')
      ? text.substring(0, text.length - 3)
      : text.replaceFirst(RegExp(r'0+$'), '');
  return 'VAT ($trimmed%)';
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
            detail: line.discountAmount > 0
                ? '${formatQuantity(line.quantity)} ${line.unit} × '
                      '${formatPesoForPrint(line.unitPrice)} '
                      '(line disc −${formatPesoForPrint(line.discountAmount)})'
                : '${formatQuantity(line.quantity)} ${line.unit} × '
                      '${formatPesoForPrint(line.unitPrice)}',
            total: formatPesoForPrint(line.total),
            // Phase 9 F2 (decision 21 §2/§4): WHERE this line was picked from.
            // A split sale names each shelf; a pre-Phase-9 sale keeps Phase 5's
            // single place; neither prints nothing rather than inventing one.
            pickUp: pickUpCaption(
              pickUp: line.pickUp,
              storedAtName: line.storedAtName,
            ),
          ),
      ],
      amounts = [
        // The discount sits between the lines and the total so the paper reconciles:
        // lines less discount is what the customer owed (decision 18).
        if (receipt.discountAmount > 0)
          ReceiptAmountRow(
            receiptDiscountLabel(receipt.discountReason),
            formatPesoForPrint(-receipt.discountAmount),
          ),
        // Decision 18: the fee was added AFTER the discount and never discounted,
        // so the paper reconciles: lines less discount plus charge is the total.
        // A zero fee prints nothing: the customer was charged for goods only.
        // Owner ruling (tender fees): the fee the shop charged for taking a
        // non-cash payment, printed from the SERVER's stored number. It is NOT
        // VAT and no tax treatment is claimed for it.
        if (receipt.paymentFee > 0)
          ReceiptAmountRow(
            'Payment fee',
            formatPesoForPrint(receipt.paymentFee),
          ),
        if (receipt.deliveryFee > 0)
          ReceiptAmountRow(
            'Delivery charge',
            formatPesoForPrint(receipt.deliveryFee),
          ),
        ReceiptAmountRow('Total', formatPesoForPrint(receipt.total)),
        // The VAT split of the NET, computed by the server. A non-VAT store says so
        // rather than printing two zeroes the customer would read as "no VAT charged".
        if (receipt.vatRegistered) ...[
          ReceiptAmountRow(
            'Vatable sales',
            formatPesoForPrint(receipt.vatableSales),
          ),
          ReceiptAmountRow(
            receiptVatLabel(receipt.vatRate),
            formatPesoForPrint(receipt.vatAmount),
          ),
        ] else
          const ReceiptAmountRow('VAT', 'Non-VAT'),
        // Every tender on its own line, so a split sale is not summarised into one
        // method and a cheque prints as pending rather than as money.
        for (final payment in receipt.payments)
          ReceiptAmountRow(
            payment.isPending
                ? '${TenderMethod.labelFor(payment.method)} (pending)'
                : TenderMethod.labelFor(payment.method),
            formatPesoForPrint(payment.amount),
          ),
        // Money RECEIVED: the tenders the server calls money in hand, so a pending
        // cheque is never printed as paid.
        ReceiptAmountRow('Paid', formatPesoForPrint(receipt.paidNow)),
        if (receipt.pendingChequeTotal > 0)
          ReceiptAmountRow(
            'Cheque pending (not paid yet)',
            formatPesoForPrint(receipt.pendingChequeTotal),
          ),
        // Same rule as the on-screen receipt: a shortfall is utang owed, not
        // negative change handed back.
        if (receipt.balanceDue > 0)
          ReceiptAmountRow(
            receipt.pendingChequeTotal > 0
                ? 'Balance due (held by the cheque)'
                : 'Balance due (utang)',
            formatPesoForPrint(receipt.balanceDue),
          )
        else
          // QA High (Phase 4 close): the SERVER's `change_given`. Deriving it here
          // printed 0.00 for a 15.00 change on a split sale.
          ReceiptAmountRow('Change', formatPesoForPrint(receipt.changeGiven)),
      ];

  final List<String> header;
  final List<({String name, String detail, String total, String? pickUp})>
  lines;
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
          // Decision 25: the OR number as a QR code, so the Bodega Checker can scan
          // the receipt with a phone to release the goods it paid for.
          if (receipt.officialReceiptNumber.isNotEmpty) ...[
            pw.Center(
              child: pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: receipt.officialReceiptNumber,
                width: 72,
                height: 72,
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Center(
              child: pw.Text(receipt.officialReceiptNumber, style: body),
            ),
            pw.SizedBox(height: 6),
          ],
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

/// One receipt as ESC/POS for the 58 mm roll: the printer's own commands,
/// ending with a fixed tear-off feed, so the paper used is the receipt's lines
/// and nothing more. This, not [buildReceiptPdf], is what the counter prints:
/// a PDF reached the thermal printer through a generic driver as PostScript
/// and printed as text down most of a roll.
Uint8List buildReceiptEscPos(PosReceipt receipt) {
  final content = ReceiptContent(receipt);
  final job = EscPosJob()
    ..text('QUEEN BUILDERS', bold: true, center: true, large: true)
    ..text('Hardware store', center: true)
    ..feed(1);
  for (final text in content.header) {
    job.text(text);
  }
  job.divider();
  for (final line in content.lines) {
    job
      ..text(line.name)
      ..row(line.detail, line.total);
    // Owner 2026-11-19: no "Pick up at" line; the staff know where goods are.
  }
  job.divider();
  for (final row in content.amounts) {
    job.row(row.label, row.amount, bold: true);
  }
  job.feed(1);
  // Decision 25: the OR number as a QR code, so the Bodega Checker can scan
  // the receipt with a phone to release the goods it paid for.
  if (receipt.officialReceiptNumber.isNotEmpty) {
    job
      ..qr(receipt.officialReceiptNumber)
      ..text(receipt.officialReceiptNumber, center: true)
      ..feed(1);
  }
  job.text('Thank you!', center: true);
  return job.finish();
}
