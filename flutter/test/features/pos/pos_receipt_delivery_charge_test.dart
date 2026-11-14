// Phase 5 F3 (decision 18): the "Delivery charge" line on the receipt.
//
// Two surfaces print the same line: the on-screen sale-complete dialog and the
// 80 mm roll document. The amount is the SERVER's `delivery_fee`, added after
// the discount; a sale with no delivery prints no line at all, because a
// "Delivery charge 0.00" reads as a charge that was made.

import 'package:client/core/format/format.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:client/features/pos/widgets/pos_receipt_dialog.dart';
import 'package:client/features/pos/widgets/receipt_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PosReceipt _receipt({double deliveryFee = 50, double total = 950}) =>
    PosReceipt(
      reference: 'TRX-20261112-0007',
      officialReceiptNumber: 'OR-20261112-0007',
      createdAt: DateTime(2026, 11, 12, 10),
      lines: const [
        PosCartLine(
          variantUomId: 1,
          productName: 'Portland cement',
          variantName: '40 kg',
          quantity: 2,
          unit: 'BAG',
          unitPrice: 450,
          availableQuantity: 10,
        ),
      ],
      paymentMethod: 'CASH',
      amountPaid: 1000,
      total: total,
      deliveryFee: deliveryFee,
    );

Future<void> _pump(WidgetTester tester, PosReceipt receipt) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PosReceiptDialog(receipt: receipt)),
      ),
    );

void main() {
  group('sale complete dialog', () {
    testWidgets('shows the delivery charge the server added', (tester) async {
      await _pump(tester, _receipt());

      expect(find.text('Delivery charge'), findsOneWidget);
      expect(find.text(formatPeso(50)), findsOneWidget);
      expect(find.text(formatPeso(950)), findsOneWidget);
    });

    testWidgets('a carried-out sale shows no delivery line', (tester) async {
      await _pump(tester, _receipt(deliveryFee: 0, total: 900));

      expect(
        find.text('Delivery charge'),
        findsNothing,
        reason: 'a zero charge would read as a charge that was made',
      );
    });
  });

  group('80 mm receipt document', () {
    test('the delivery charge sits between the discount and the total', () {
      final content = ReceiptContent(_receipt());
      final labels = [for (final row in content.amounts) row.label];

      expect(labels, contains('Delivery charge'));
      expect(
        labels.indexOf('Delivery charge'),
        lessThan(labels.indexOf('Total')),
        reason: 'the charge is part of the total, so it must be above it',
      );
      final row = content.amounts.firstWhere(
        (row) => row.label == 'Delivery charge',
      );
      expect(row.amount, formatPesoForPrint(50));
      expect(
        row.amount,
        contains('PHP'),
        reason: 'the bundled font has no peso glyph',
      );
    });

    test('a legacy receipt with delivery_fee 0 prints no charge line', () {
      final content = ReceiptContent(_receipt(deliveryFee: 0, total: 900));
      expect([
        for (final row in content.amounts) row.label,
      ], isNot(contains('Delivery charge')));
    });

    test('the documented default keeps a pre-B3 receipt readable', () {
      expect(_receipt(deliveryFee: 0).deliveryFee, 0);
    });
  });
}
