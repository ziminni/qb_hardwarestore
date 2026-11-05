// The sales receipt on paper (UC-11). Before 2026-11-04 the receipt only
// existed on screen; the manuscript promises a printed one from a thermal
// printer. These pin what goes on the roll and that the dialog's Print button
// hands exactly this sale to the printer, keeping the dialog when it fails.

import 'package:client/data/models/pos_transaction.dart';
import 'package:client/features/pos/widgets/pos_receipt_dialog.dart';
import 'package:client/features/pos/widgets/receipt_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PosReceipt _receipt({required double paid, required double total}) =>
    PosReceipt(
      reference: 'TRX-20261104-0007',
      officialReceiptNumber: 'OR-20261104-0007',
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
  test('the roll carries the OR number, the lines and the change', () {
    final content = ReceiptContent(_receipt(paid: 500, total: 315));

    expect(content.header, contains('Receipt: OR-20261104-0007'));
    expect(content.lines.single.name, 'Portland Cement · 40 kg');
    expect(content.lines.single.total, 'PHP 315.00');
    expect(
      content.amounts.map((row) => '${row.label} ${row.amount}'),
      ['Total PHP 315.00', 'Paid PHP 500.00', 'Change PHP 185.00'],
    );
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

  testWidgets('Print receipt sends this sale to the printer', (tester) async {
    final printer = _FakePrinter();
    final receipt = _receipt(paid: 500, total: 315);
    await _pump(tester, receipt, printer);

    await tester.tap(find.text('Print receipt'));
    await tester.pumpAndSettle();

    expect(printer.printed, [receipt]);
  });

  testWidgets('a failed print says so and keeps the receipt open', (
    tester,
  ) async {
    await _pump(tester, _receipt(paid: 500, total: 315), _FakePrinter(fail: true));

    await tester.tap(find.text('Print receipt'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not print the receipt'), findsOneWidget);
    expect(find.text('Transaction complete'), findsOneWidget);
  });
}
