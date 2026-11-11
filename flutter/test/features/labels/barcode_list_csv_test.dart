// Phase 4 Task F2: the CSV half of the barcode masterlist.
//
// Excel opens a UTF-8 file as mojibake unless it starts with a BOM, and a product
// name with a comma in it silently shifts every following column unless the field
// is quoted the RFC 4180 way. Both are cheap to get wrong and impossible to notice
// on screen, so they are pinned here.

import 'dart:convert';
import 'dart:typed_data';

import 'package:client/features/labels/barcode_list_csv.dart';
import 'package:client/features/labels/barcode_list_document.dart';
import 'package:flutter_test/flutter_test.dart';

BarcodeListRow row({
  String productName = 'Circuit Breaker',
  String variantName = '20A 1-pole',
  String unitCode = 'PC',
  double price = 315,
  String code = 'QB000013-0',
}) => BarcodeListRow(
  productName: productName,
  variantName: variantName,
  unitCode: unitCode,
  price: price,
  code: code,
);

/// CRLF between records, as RFC 4180 asks for.
List<String> records(String csv) =>
    csv.split('\r\n').where((line) => line.isNotEmpty).toList();

void main() {
  group('barcodeListCsv', () {
    test('a header row names every column', () {
      expect(
        records(barcodeListCsv(const [])).single,
        'Product,Variant,Unit,Price,Code',
      );
    });

    test('one row per code, with the price as a plain number', () {
      final csv = barcodeListCsv([
        row(),
        row(
          productName: 'PVC Pipe',
          variantName: '1/2 inch',
          price: 95.5,
          code: 'QB000014-8',
        ),
      ]);

      final lines = records(csv);
      expect(lines[1], 'Circuit Breaker,20A 1-pole,PC,315.00,QB000013-0');
      expect(lines[2], 'PVC Pipe,1/2 inch,PC,95.50,QB000014-8');
    });

    test('a comma in a name is quoted, not a new column', () {
      final csv = barcodeListCsv([row(productName: 'Cement, Portland 40kg')]);

      expect(
        records(csv)[1],
        '"Cement, Portland 40kg",20A 1-pole,PC,315.00,QB000013-0',
      );
    });

    test('a double quote is doubled inside a quoted field', () {
      final csv = barcodeListCsv([row(variantName: '20A "1-pole"')]);

      expect(
        records(csv)[1],
        'Circuit Breaker,"20A ""1-pole""",PC,315.00,QB000013-0',
      );
    });

    test('a newline in a name keeps the record in one quoted field', () {
      final csv = barcodeListCsv([row(productName: 'Circuit Breaker\n20A')]);

      // The newline stays inside the quotes: the record is written as
      // `"Circuit Breaker\n20A",...` and the record count is still header + 1.
      expect(csv.split('\r\n').length, 3);
      expect(csv.contains('"Circuit Breaker\n20A"'), isTrue);
    });

    test('a peso sign survives as UTF-8 text', () {
      final csv = barcodeListCsv([row(productName: '₱ Peso sign cable ₱')]);

      expect(csv.contains('₱ Peso sign cable ₱'), isTrue);
    });

    test('the code column is never quoted or altered', () {
      final csv = barcodeListCsv([row(code: '4800016123450')]);

      expect(records(csv)[1].endsWith(',4800016123450'), isTrue);
    });
  });

  // A name beginning `=`, `+`, `-`, `@`, TAB or CR is a formula to Excel and
  // LibreOffice, so it runs on open (OWASP CSV injection). The apostrophe makes
  // the cell text; it is not shown in the cell.
  group('formula injection', () {
    for (final trigger in ['=', '+', '-', '@', '\t', '\r']) {
      final label = switch (trigger) {
        '=' => '=SUM(A1)',
        '+' => '+SUM(A1)',
        '-' => '-SUM(A1)',
        '@' => '@SUM(A1)',
        '\t' => 'TAB',
        _ => 'CR',
      };

      test('a product name starting with $label gains an apostrophe', () {
        final csv = barcodeListCsv([row(productName: '$trigger$label')]);

        expect(csv.contains("'$trigger$label"), isTrue);
      });
    }

    test('a code starting with a trigger character gains an apostrophe', () {
      final csv = barcodeListCsv([row(code: '@code')]);

      expect(records(csv)[1].endsWith(",'@code"), isTrue);
    });

    test('a name needing both prefix and quoting gets both', () {
      final csv = barcodeListCsv([row(productName: '=1,2')]);

      expect(records(csv)[1], '"\'=1,2",20A 1-pole,PC,315.00,QB000013-0');
    });

    test('a name that is not formula-like is left alone', () {
      final csv = barcodeListCsv([row(productName: 'Pump = duty')]);

      expect(records(csv)[1], 'Pump = duty,20A 1-pole,PC,315.00,QB000013-0');
    });

    test('the price column stays a plain number so totals still work', () {
      final csv = barcodeListCsv([row(price: 1480)]);

      expect(
        records(csv)[1],
        'Circuit Breaker,20A 1-pole,PC,1480.00,QB000013-0',
      );
    });
  });

  group('barcodeListCsvBytes', () {
    test('starts with the UTF-8 BOM so Excel reads the peso sign', () {
      final bytes = barcodeListCsvBytes([row(productName: '₱1,480.00')]);

      expect(bytes.sublist(0, 3), [0xEF, 0xBB, 0xBF]);
    });

    test('is UTF-8 after the BOM', () {
      final bytes = barcodeListCsvBytes([row(productName: '₱')]);
      final text = utf8.decode(bytes.sublist(3));

      expect(text.contains('₱'), isTrue);
    });

    test('the CSV text is the source of the bytes', () {
      final rows = [row(), row(productName: 'PVC Pipe')];
      final bytes = barcodeListCsvBytes(rows);

      expect(
        utf8.decode(Uint8List.fromList(bytes.sublist(3))),
        barcodeListCsv(rows),
      );
    });
  });
}
