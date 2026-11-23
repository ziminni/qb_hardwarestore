import 'dart:typed_data';

import 'package:client/core/format/format.dart';
import 'package:client/features/reports/report_pdf.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart'
    show SalesDocumentLine, salesQty;
import 'package:client/shared/widgets/settings_side_layout.dart'
    show StoreInformationPanel;

/// The quotation the manager emails to whoever asked for bulk-buy prices.
///
/// It goes through the reports' letterhead builder ([renderReportPdf]) rather
/// than growing a second PDF layout: the store header, the page footer and the
/// column headings are then the same paper a management report prints on, and
/// the pesos are spelled `PHP` for the same reason (the bundled font has no ₱).
///
/// Deliberately NOT a tax document: a quotation promises a price, so the paper
/// carries no BIR wording of any kind - no "Official Receipt", no invoice
/// number, nothing a customer could mistake for a receipt.
class QuotationPdf {
  const QuotationPdf._();

  /// The file name the share sheet offers.
  static String fileName(String number) => '$number.pdf';
}

/// What the quotation prints, before any layout. Split out so a test can read
/// the content without decoding a PDF.
ReportPdfContent quotationPdfContent({
  required String number,
  required String customer,
  required DateTime validUntil,
  required List<SalesDocumentLine> lines,
  required num total,
}) => ReportPdfContent(
  title: 'Quotation $number',
  period: 'Valid until ${formatDate(validUntil)}',
  filters: const [],
  // shortcut: static store header until store details are user-editable, the
  // same source every report's letterhead reads.
  storeName: StoreInformationPanel.storeName,
  // The customer rides as a tile, not a "Filters:" line: a quotation is not a
  // filtered view of anything, it is a promise to ONE account.
  kpis: [
    (label: 'Customer', value: customer, caption: null),
    (label: 'Total', value: formatPesoForPrint(total), caption: null),
  ],
  columns: const ['Item', 'Qty', 'Unit price', 'Amount'],
  rows: [
    for (final line in lines)
      [
        line.name,
        salesQty(line.qty),
        formatPesoForPrint(line.unitPrice),
        formatPesoForPrint(line.subtotal),
      ],
  ],
  emptyMessage: 'No items',
);

/// The quotation as PDF bytes, ready to share or print.
Future<Uint8List> renderQuotationPdf({
  required String number,
  required String customer,
  required DateTime validUntil,
  required List<SalesDocumentLine> lines,
  required num total,
}) {
  final content = quotationPdfContent(
    number: number,
    customer: customer,
    validUntil: validUntil,
    lines: lines,
    total: total,
  );
  return renderReportPdf(
    title: content.title,
    period: content.period,
    filters: content.filters,
    storeName: content.storeName,
    kpis: content.kpis,
    columns: content.columns,
    rows: content.rows,
    emptyMessage: content.emptyMessage,
  );
}
