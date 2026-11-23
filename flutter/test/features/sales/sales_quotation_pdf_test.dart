// A quotation has to LEAVE the building: the manager emails it to whoever asked
// for bulk-buy prices before any order exists. Until this card the sheet could
// only be read on screen, so the price promise never reached the requester.
//
// The paper is built from the same lines the sheet shows, through the reports'
// letterhead builder (`renderReportPdf`), so the store header, the page footer
// and the column headings cannot drift between a report and a quotation.
//
// WHAT THIS DOES NOT PROVE: that the bytes reach a printer or a share sheet
// (`Printing.sharePdf`), which needs a platform channel. The content is pinned
// here, and the sheet's button is pinned in the widget test.

import 'package:client/core/format/format.dart';
import 'package:client/features/reports/report_pdf.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/features/sales/widgets/sales_quotation_pdf.dart';
import 'package:client/shared/widgets/settings_side_layout.dart';
import 'package:flutter_test/flutter_test.dart';

const _lines = [
  SalesDocumentLine(name: 'Portland Cement (Bag)', qty: 40, unitPrice: 250),
  SalesDocumentLine(name: 'Common Nail 2" (Kilo)', qty: 2.5, unitPrice: 12),
];

ReportPdfContent _content() => quotationPdfContent(
  number: 'QT-20261123-0001',
  customer: 'Dela Cruz Construction',
  validUntil: DateTime(2026, 12, 23),
  lines: _lines,
  total: 10030,
);

/// Every string the paper can print, in one list, so a forbidden word is found
/// wherever it was introduced.
List<String> _allText(ReportPdfContent content) => [
  content.title,
  content.period,
  content.generatedLine,
  ...content.letterheadLines,
  ...content.filterLines,
  ...content.kpis.map((kpi) => '${kpi.label} ${kpi.value}'),
  ...content.columns,
  for (final row in content.rows) ...row,
];

void main() {
  group('the quotation paper', () {
    test('names the quotation, the customer and the day the price holds', () {
      final content = _content();

      expect(content.title, 'Quotation QT-20261123-0001');
      expect(content.period, 'Valid until Dec 23, 2026');
      expect(content.kpis.first, (
        label: 'Customer',
        value: 'Dela Cruz Construction',
        caption: null,
      ), reason: 'the requester sends the paper back, so it must name them');
    });

    test('carries the store header from the configured store details', () {
      expect(_content().letterheadLines.first, StoreInformationPanel.storeName);
    });

    test('lists every line at the agreed price, in printed pesos', () {
      final content = _content();

      expect(content.columns, ['Item', 'Qty', 'Unit price', 'Amount']);
      expect(content.rows, [
        [
          'Portland Cement (Bag)',
          '40',
          formatPesoForPrint(250),
          formatPesoForPrint(10000),
        ],
        [
          'Common Nail 2" (Kilo)',
          '2.5',
          formatPesoForPrint(12),
          formatPesoForPrint(30),
        ],
      ]);
      expect(
        content.rows.first[2],
        startsWith('PHP '),
        reason: 'the bundled font has no peso glyph, so paper spells PHP',
      );
    });

    test('shows the total the customer is asked to agree to', () {
      final content = _content();

      final total = content.kpis.last;
      expect(total.label, 'Total');
      expect(total.value, formatPesoForPrint(10030));
    });

    test('carries no BIR wording: a quotation is not a tax document', () {
      final text = _allText(_content()).join('\n');

      expect(text.toUpperCase(), isNot(contains('BIR')));
      expect(text.toLowerCase(), isNot(contains('official receipt')));
    });
  });

  group('renderQuotationPdf', () {
    test('builds a real, non-empty PDF', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final bytes = await renderQuotationPdf(
        number: 'QT-20261123-0001',
        customer: 'Dela Cruz Construction',
        validUntil: DateTime(2026, 12, 23),
        lines: _lines,
        total: 10030,
      );

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    });

    test('long quotations continue over pages instead of clipping', () async {
      TestWidgetsFlutterBinding.ensureInitialized();

      final bytes = await renderQuotationPdf(
        number: 'QT-20261123-0002',
        customer: 'Dela Cruz Construction',
        validUntil: DateTime(2026, 12, 23),
        lines: [
          for (var index = 1; index <= 120; index++)
            SalesDocumentLine(
              name: 'Material $index (Bag)',
              qty: index.toDouble(),
              unitPrice: 250,
            ),
        ],
        total: 250 * 7260,
      );

      final text = String.fromCharCodes(bytes);
      expect(
        RegExp(r'/Type\s*/Page[^s]').allMatches(text).length,
        greaterThan(1),
      );
    });
  });
}
