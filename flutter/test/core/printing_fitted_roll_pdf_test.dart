import 'package:client/core/printing/fitted_roll_pdf.dart';
import 'package:client/data/models/pos_transaction.dart';
import 'package:client/features/pos/widgets/receipt_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';

void main() {
  test('a receipt prints at its real size, not an endless roll', () async {
    final pdf = await buildReceiptPdf(
      PosReceipt(
        reference: 'TRX-20261118-0010',
        officialReceiptNumber: 'OR-20261118-0010',
        createdAt: DateTime(2026, 11, 18, 10, 36),
        lines: const [
          PosCartLine(
            variantUomId: 1,
            productName: 'Faucet',
            variantName: 'Standard',
            quantity: 1,
            unit: 'pc',
            unitPrice: 225,
            availableQuantity: 9,
          ),
        ],
        paymentMethod: 'CASH',
        amountPaid: 225,
        total: 225,
        changeGiven: 0,
      ),
    );
    final format = fittedRollFormat(pdf);
    expect(format.width, closeTo(PdfPageFormat.roll80.width, 0.01));
    expect(format.height.isFinite, isTrue);
    // A one-line receipt with its QR code is a short strip.
    expect(format.height / PdfPageFormat.mm, inInclusiveRange(60, 200));
  });
}
