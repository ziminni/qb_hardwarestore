// Phase 6 Task 6 (decision 14): the sticker document.
//
// One PDF page = one 50 × 30 mm sticker. The assertions are on the PAYLOAD
// (`labelPages`, the pure seam that feeds the document) rather than on pixels, so
// a wrong page count or a printed factory EAN fails here instead of on paper.

import 'package:client/features/labels/label_document.dart';
import 'package:flutter_test/flutter_test.dart';

LabelRequest request({
  String code = 'QB000013-0',
  String productName = 'Circuit Breaker',
  String variantName = '20A 1-pole',
  String unitName = 'PC',
  int copies = 1,
}) => LabelRequest(
  code: code,
  productName: productName,
  variantName: variantName,
  unitName: unitName,
  copies: copies,
);

/// How many pages a PDF really carries: the object dictionary marks each one.
int pageCount(List<int> bytes) {
  final text = String.fromCharCodes(bytes);
  return RegExp(r'/Type\s*/Page[^s]').allMatches(text).length;
}

void main() {
  group('labelPages', () {
    test('one page per copy, in request order', () {
      final pages = labelPages([
        request(code: 'QB000012-3', copies: 3),
        request(code: 'QB000013-0', copies: 2),
      ]);

      expect(pages, hasLength(5));
      expect(pages.map((page) => page.code).toList(), [
        'QB000012-3',
        'QB000012-3',
        'QB000012-3',
        'QB000013-0',
        'QB000013-0',
      ]);
    });

    test('a unit with a factory EAN is skipped, not relabelled', () {
      final pages = labelPages([
        request(code: 'QB000013-0', copies: 2),
        request(code: '4800016123450', copies: 5),
      ]);

      expect(pages, hasLength(2));
      expect(pages.every((page) => page.code.startsWith('QB')), isTrue);
    });

    test('a scanned-into-the-field code is normalised', () {
      final pages = labelPages([request(code: ' qb000013-0 ')]);

      expect(pages.single.code, 'QB000013-0');
    });

    test('zero copies prints nothing', () {
      expect(labelPages([request(copies: 0)]), isEmpty);
    });

    test('a page carries the names and the unit, and never a price', () {
      final page = labelPages([request()]).single;

      expect(page.productName, 'Circuit Breaker');
      expect(page.variantName, '20A 1-pole');
      expect(page.unitName, 'PC');
    });
  });

  group('buildLabelPdf', () {
    test('renders one page per sticker', () async {
      final bytes = await buildLabelPdf([
        request(code: 'QB000012-3', copies: 3),
        request(code: 'QB000013-0', copies: 1),
      ]);

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(pageCount(bytes), 4);
    });

    test('skips the factory-EAN row, so it cannot reach paper', () async {
      final bytes = await buildLabelPdf([
        request(code: 'QB000013-0', copies: 2),
        request(code: '4800016123450', copies: 4),
      ]);

      expect(pageCount(bytes), 2);
    });

    test('an empty request list is an empty document, not a crash', () async {
      final bytes = await buildLabelPdf([]);

      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(pageCount(bytes), 0);
    });

    test('a very long product name still renders one page', () async {
      // The name is CLIPPED to one line (pw.TextOverflow.clip); the code text is
      // never truncated, and nothing here may throw.
      final bytes = await buildLabelPdf([
        request(productName: 'Galvanised Steel Angle Bar ' * 12),
      ]);

      expect(pageCount(bytes), 1);
    });
  });
}
