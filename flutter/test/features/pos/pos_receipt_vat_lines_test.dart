// Phase 4 Task F4 (decision 18): Discount, Vatable sales and VAT on the receipt.
//
// Two surfaces print the same three lines: the on-screen sale-complete dialog and the
// 80 mm roll document. The numbers are the SERVER's; these tests pin the LABELS and
// the non-VAT case, which is where a wrong sentence would reach the customer's hand.

import 'package:client/data/models/pos_transaction.dart';
import 'package:client/features/pos/widgets/pos_receipt_dialog.dart';
import 'package:client/features/pos/widgets/receipt_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PosReceipt _receipt({
  double total = 850,
  double discountAmount = 150,
  String discountReason = 'bulk order',
  double vatableSales = 758.93,
  double vatAmount = 91.07,
  bool vatRegistered = true,
  double vatRate = 12,
}) => PosReceipt(
  reference: 'TRX-20261111-0007',
  officialReceiptNumber: 'OR-20261111-0007',
  createdAt: DateTime(2026, 11, 11, 9),
  lines: const [
    PosCartLine(
      variantUomId: 1,
      productName: 'Portland cement',
      variantName: '40 kg',
      quantity: 2,
      unit: 'BAG',
      unitPrice: 500,
      availableQuantity: 10,
    ),
  ],
  paymentMethod: 'CASH',
  amountPaid: total,
  total: total,
  discountAmount: discountAmount,
  discountReason: discountReason,
  vatableSales: vatableSales,
  vatAmount: vatAmount,
  vatRegistered: vatRegistered,
  vatRate: vatRate,
);

Future<void> _pump(WidgetTester tester, PosReceipt receipt) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PosReceiptDialog(receipt: receipt)),
      ),
    );

void main() {
  group('sale complete dialog', () {
    testWidgets('shows the discount with its reason, then the VAT split', (
      tester,
    ) async {
      await _pump(tester, _receipt());

      expect(find.text('Discount (bulk order)'), findsOneWidget);
      expect(find.text('-₱150.00'), findsOneWidget);
      expect(find.text('Vatable sales'), findsOneWidget);
      expect(find.text('₱758.93'), findsOneWidget);
      expect(find.text('VAT (12%)'), findsOneWidget);
      expect(find.text('₱91.07'), findsOneWidget);
      // The total is the net the customer was charged; the same figure is also the
      // amount paid, so it appears twice.
      expect(find.text('₱850.00'), findsNWidgets(2));
    });

    testWidgets('a non-VAT store says Non-VAT instead of printing zeroes', (
      tester,
    ) async {
      await _pump(
        tester,
        _receipt(vatRegistered: false, vatableSales: 0, vatAmount: 0),
      );

      expect(find.text('Non-VAT'), findsOneWidget);
      expect(find.text('Vatable sales'), findsNothing);
    });

    testWidgets('a sale with no discount shows no discount row', (
      tester,
    ) async {
      await _pump(tester, _receipt(discountAmount: 0, discountReason: ''));

      expect(find.textContaining('Discount ('), findsNothing);
      expect(find.text('Discount'), findsNothing);
    });
  });

  group('80 mm receipt document', () {
    test('prints discount, vatable sales and VAT in that order', () {
      final content = ReceiptContent(_receipt());
      final labels = [for (final row in content.amounts) row.label];

      expect(labels, contains('Discount (bulk order)'));
      expect(labels, contains('Vatable sales'));
      expect(labels, contains('VAT (12%)'));
      expect(
        labels.indexOf('Discount (bulk order)'),
        lessThan(labels.indexOf('Total')),
        reason: 'a discount reads as a deduction before the total it produces',
      );
      // The peso glyph has no bundled font, so the roll uses the print format.
      final discount = content.amounts.firstWhere(
        (row) => row.label.startsWith('Discount'),
      );
      expect(discount.amount, contains('150.00'));
    });

    test('a non-VAT store prints Non-VAT on the roll', () {
      final content = ReceiptContent(
        _receipt(vatRegistered: false, vatableSales: 0, vatAmount: 0),
      );

      expect(content.amounts.any((row) => row.amount == 'Non-VAT'), isTrue);
    });

    test('the VAT label carries the rate, and drops trailing zeroes', () {
      expect(receiptVatLabel(12), 'VAT (12%)');
      expect(receiptVatLabel(12.5), 'VAT (12.5%)');
      expect(receiptVatLabel(0), 'VAT');
    });

    test('a discount with no reason is labelled plainly', () {
      expect(receiptDiscountLabel(''), 'Discount');
      expect(receiptDiscountLabel('senior'), 'Discount (senior)');
    });
  });
}
