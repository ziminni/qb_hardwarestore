// The sales receipt on paper (UC-11). Before 2026-11-04 the receipt only
// existed on screen; the manuscript promises a printed one from a thermal
// printer. These pin what goes on the roll and that the dialog's Print button
// hands exactly this sale to the printer, keeping the dialog when it fails.

import 'package:client/core/printing/escpos.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:client/features/pos/widgets/pos_receipt_dialog.dart';
import 'package:client/features/pos/widgets/receipt_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/escpos_reader.dart';

PosReceipt _receipt({required double paid, required double total}) =>
    PosReceipt(
      reference: 'TRX-20261104-0007',
      officialReceiptNumber: 'OS-20261104-0007',
      createdAt: DateTime(2026, 11, 4, 9, 30),
      lines: const [
        PosCartLine(
          variantUomId: 1,
          productName: 'Portland Cement',
          variantName: '40 kg',
          quantity: 2,
          unit: 'bag',
          unitPrice: 157.5,
          availableQuantity: 50,
        ),
      ],
      paymentMethod: 'CASH',
      amountPaid: paid,
      total: total,
      // QA High (Phase 4 close): the receipt prints the SERVER's change, so a
      // fixture has to state it. These predate split payment, so the tendered
      // amount over the total is the change the drawer paid.
      changeGiven: (paid - total).clamp(0, double.infinity),
    );

class _FakePrinter implements ReceiptPrinter {
  _FakePrinter({this.fail = false});
  final bool fail;
  final printed = <PosReceipt>[];

  @override
  Future<void> print(PosReceipt receipt) async {
    if (fail) throw Exception('printer offline');
    printed.add(receipt);
  }
}

Future<void> _pump(
  WidgetTester tester,
  PosReceipt receipt,
  ReceiptPrinter printer,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: PosReceiptDialog(receipt: receipt, printer: printer),
    ),
  ),
);

void main() {
  test('the roll carries the OS number, the lines and the change', () {
    final content = ReceiptContent(_receipt(paid: 500, total: 315));

    expect(content.header, contains('Order Slip: OS-20261104-0007'));
    expect(content.lines.single.name, 'Portland Cement · 40 kg');
    expect(content.lines.single.total, 'PHP 315.00');
    // Phase 4 F4: the VAT split sits between the total and what was paid. This
    // fixture is a VAT-registered sale with no discount and no stored rate.
    expect(content.amounts.map((row) => '${row.label} ${row.amount}'), [
      'Total PHP 315.00',
      'Vatable sales PHP 0.00',
      'VAT PHP 0.00',
      'Paid PHP 500.00',
      'Change PHP 185.00',
    ]);
  });

  test('an underpaid sale prints the utang, never negative change', () {
    final content = ReceiptContent(_receipt(paid: 1, total: 315));

    expect(content.amounts.last.label, 'Balance due (utang)');
    expect(content.amounts.last.amount, 'PHP 314.00');
  });

  test('no peso sign reaches paper: the bundled font has no glyph for it', () {
    final content = ReceiptContent(_receipt(paid: 500, total: 315));
    final text = [
      ...content.header,
      for (final line in content.lines) ...[line.detail, line.total],
      for (final row in content.amounts) row.amount,
    ].join('\n');

    expect(text, isNot(contains('₱')));
  });

  test('the receipt renders to a PDF', () async {
    final bytes = await buildReceiptPdf(_receipt(paid: 500, total: 315));

    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
  });

  testWidgets('Print order slip sends this sale to the printer', (tester) async {
    final printer = _FakePrinter();
    final receipt = _receipt(paid: 500, total: 315);
    await _pump(tester, receipt, printer);

    await tester.tap(find.text('Print order slip'));
    await tester.pumpAndSettle();

    expect(printer.printed, [receipt]);
  });

  testWidgets('a failed print says so and keeps the order slip open', (
    tester,
  ) async {
    await _pump(
      tester,
      _receipt(paid: 500, total: 315),
      _FakePrinter(fail: true),
    );

    await tester.tap(find.text('Print order slip'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not print the order slip'), findsOneWidget);
    expect(find.text('Transaction complete'), findsOneWidget);
  });

  // 2026-11-18: a PDF sent to the GOOJPRT PT-210 through the Mac's "Generic
  // PostScript" driver printed as PostScript text down most of a roll, twice.
  // What the counter prints is the printer's own commands, and only these.
  test('the printed order slip is ESC/POS for a 58 mm roll, not a document', () {
    final bytes = buildReceiptEscPos(_receipt(paid: 500, total: 315));
    final lines = escPosLines(bytes);

    expect(bytes.take(2), [0x1B, 0x40]);
    expect(String.fromCharCodes(bytes), isNot(contains('%PDF')));
    expect(lines, contains('ORDER SLIP'));
    expect(lines, contains('Order Slip: OS-20261104-0007'));
    expect(lines, contains('Not an Official Receipt'));
    expect(lines, contains('Portland Cement - 40 kg'));
    expect(lines, contains('2 bag x PHP 157.50${' ' * 4}PHP 315.00'));
    expect(lines, contains('Change${' ' * 16}PHP 185.00'));
    for (final line in lines) {
      expect(line.length, lessThanOrEqualTo(roll58Columns), reason: line);
    }
  });

  test('the printed order slip carries the OS number as a QR (decision 25)', () {
    final lines = escPosLines(
      buildReceiptEscPos(_receipt(paid: 500, total: 315)),
    );

    expect(lines, contains('[QR OS-20261104-0007]'));
  });

  test('the paper ends a fixed feed after the last line', () {
    final bytes = buildReceiptEscPos(_receipt(paid: 500, total: 315));
    final lines = escPosLines(bytes);

    expect(escPosFinalFeed(bytes), tearOffFeedLines);
    expect(lines.lastWhere((line) => line.isNotEmpty).trim(), 'Thank you!');
    // A one-line sale is a short strip, not a roll.
    expect(lines.length, lessThan(40));
  });
}
