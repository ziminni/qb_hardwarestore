// Store-ops Phase 1: tagging a sale with the paper BIR Official Receipt's
// Invoice number.
//
// Three surfaces, so three small tests rather than one large one:
//
// * the SLIP prints `OR Invoice No.: <n>` under the OS number, and prints
//   nothing when the sale was never tagged (an invented BIR number on a
//   customer's paper would be a number the shop never wrote in its booklet);
// * the attach DIALOG posts what the cashier typed and, on `INVOICE_ALREADY_TAGGED`,
//   shows the number already on the slip instead of a bare "conflict";
// * the checkout BODY carries `invoice_no` only when the switch was on.

// `pos_transaction.dart` also declares a legacy four-field `PosCheckoutResult`;
// this test uses the LIVE one from the service, which carries the invoice no.
import 'package:client/data/models/pos_transaction.dart' hide PosCheckoutResult;
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/pos/widgets/pos_attach_or_dialog.dart';
import 'package:client/features/pos/widgets/receipt_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/escpos_reader.dart';

PosReceipt _receipt({String invoiceNo = ''}) => PosReceipt(
  reference: 'TRX-20261122-0007',
  officialReceiptNumber: 'OS-20261122-0007',
  createdAt: DateTime(2026, 11, 22, 9, 30),
  lines: const [
    PosCartLine(
      variantUomId: 1,
      productName: 'Portland Cement',
      variantName: '40 kg',
      quantity: 2,
      unit: 'BAG',
      unitPrice: 157.5,
      availableQuantity: 50,
    ),
  ],
  paymentMethod: 'CASH',
  amountPaid: 315,
  total: 315,
  invoiceNo: invoiceNo,
);

/// A sale body as `POST /transactions/attach-invoice/` answers it.
PosCheckoutResult _taggedSale({String invoiceNo = 'BIR-000123'}) =>
    PosCheckoutResult.fromJson({
      'id': 7,
      'transaction_no': 'TRX-20261122-0007',
      'trans_date': '2026-11-22T09:30:00Z',
      'grand_total': '315.00',
      'invoice_no': invoiceNo,
      'receipt': {'or_number': 'OS-20261122-0007'},
      'items': [
        {
          'variant_uom': 1,
          'qty': '2.00',
          'unit_price': '157.50',
          'subtotal': '315.00',
          'product_name': 'Portland Cement',
          'variant_name': '40 kg',
          'variant_uom_code': 'BAG',
        },
      ],
      'payments': [
        {'method': 'CASH', 'amount_tendered': '315.00'},
      ],
    });

void main() {
  group('order slip', () {
    test('prints the OR invoice no. under the OS number', () {
      final content = ReceiptContent(_receipt(invoiceNo: 'BIR-000123'));

      expect(content.header.first, 'Order Slip: OS-20261122-0007');
      expect(content.header, contains('OR Invoice No.: BIR-000123'));
    });

    test('prints nothing about an invoice on an untagged sale', () {
      final content = ReceiptContent(_receipt());

      expect(content.header.where((line) => line.contains('Invoice')), isEmpty);
    });

    test('the ESC/POS roll carries the invoice line', () {
      final text = escPosLines(
        buildReceiptEscPos(_receipt(invoiceNo: 'BIR-000123')),
      ).join('\n');

      expect(text, contains('OR Invoice No.: BIR-000123'));
    });
  });

  group('attach OR dialog', () {
    testWidgets('sends what the cashier typed and shows the tagged sale', (
      tester,
    ) async {
      String? sentNumber;
      String? sentInvoice;
      bool? sentReplace;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosAttachOrDialog(
              onReprint: (_) {},
              attach:
                  ({
                    required number,
                    required invoiceNo,
                    required replace,
                  }) async {
                    sentNumber = number;
                    sentInvoice = invoiceNo;
                    sentReplace = replace;
                    return _taggedSale();
                  },
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(PosAttachOrDialog.numberFieldKey),
        'OS-20261122-0007',
      );
      await tester.enterText(
        find.byKey(PosAttachOrDialog.invoiceFieldKey),
        'bir-000123',
      );
      await tester.tap(find.text('Attach'));
      await tester.pumpAndSettle();

      expect(sentNumber, 'OS-20261122-0007');
      expect(sentInvoice, 'bir-000123');
      expect(sentReplace, isFalse);
      // The sale summary, then the invoice no. the SERVER stored.
      expect(find.text('OR Invoice No.: BIR-000123'), findsOneWidget);
      expect(find.byKey(PosAttachOrDialog.reprintKey), findsOneWidget);
    });

    testWidgets('a 409 shows the number already on the slip', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosAttachOrDialog(
              onReprint: (_) {},
              attach:
                  ({
                    required number,
                    required invoiceNo,
                    required replace,
                  }) async {
                    throw const PosServiceException(
                      'This sale is already tagged with OR invoice no. BIR-000001. '
                      'Ask a Store Manager or Admin to replace it.',
                      code: 'INVOICE_ALREADY_TAGGED',
                    );
                  },
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(PosAttachOrDialog.numberFieldKey),
        'OS-20261122-0007',
      );
      await tester.enterText(
        find.byKey(PosAttachOrDialog.invoiceFieldKey),
        'BIR-000002',
      );
      await tester.tap(find.text('Attach'));
      await tester.pumpAndSettle();

      expect(find.textContaining('already tagged'), findsOneWidget);
      expect(find.text('On the slip now: BIR-000001'), findsOneWidget);
      // A cashier is told who can fix it, and gets no Replace box.
      expect(find.byKey(PosAttachOrDialog.replaceCheckboxKey), findsNothing);
    });

    testWidgets('a manager gets the Replace box after a 409', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosAttachOrDialog(
              canReplace: true,
              onReprint: (_) {},
              attach:
                  ({
                    required number,
                    required invoiceNo,
                    required replace,
                  }) async {
                    throw const PosServiceException(
                      'This sale is already tagged with OR invoice no. BIR-000001.',
                      code: 'INVOICE_ALREADY_TAGGED',
                    );
                  },
            ),
          ),
        ),
      );

      await tester.enterText(
        find.byKey(PosAttachOrDialog.numberFieldKey),
        'OS-20261122-0007',
      );
      await tester.enterText(
        find.byKey(PosAttachOrDialog.invoiceFieldKey),
        'BIR-000002',
      );
      await tester.tap(find.text('Attach'));
      await tester.pumpAndSettle();

      expect(find.byKey(PosAttachOrDialog.replaceCheckboxKey), findsOneWidget);
    });
  });

  group('checkout body', () {
    test('carries invoice_no only when one was typed', () {
      // The assertion is on the REQUEST body, which is where `invoice_no` becomes
      // part of the sale's own transaction on the server.
      Map<String, dynamic> body({String? invoiceNo}) => checkoutBody(
        customerId: 1,
        items: const [
          PosCheckoutItem(variantUomId: 3, quantity: 2, unitPrice: 10),
        ],
        payments: const [
          PosCheckoutPayment(method: 'CASH', amountTendered: 20),
        ],
        invoiceNo: invoiceNo,
      );

      expect(
        body(invoiceNo: ' bir-000123 '),
        containsPair('invoice_no', 'bir-000123'),
      );
      expect(body().containsKey('invoice_no'), isFalse);
      expect(body(invoiceNo: '   ').containsKey('invoice_no'), isFalse);
    });
  });
}
