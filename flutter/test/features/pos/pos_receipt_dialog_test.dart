import 'package:client/data/models/pos_transaction.dart'
    hide PosCheckoutResult;
// The model file declares an older, unrelated `PosCheckoutResult`; the JSON parser
// this test exercises lives beside the service.
import 'package:client/data/services/pos_service.dart' show PosCheckoutResult;
import 'package:client/features/pos/widgets/pos_receipt_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PosReceipt _receipt({required double paid, required double total}) =>
    PosReceipt(
      reference: 'TRX-20261024-0038',
      officialReceiptNumber: 'OR-20261024-0038',
      createdAt: DateTime(2026, 10, 24, 12),
      lines: const [],
      paymentMethod: 'CASH',
      amountPaid: paid,
      total: total,
      changeGiven: (paid - total).clamp(0, double.infinity),
    );

Future<void> _pump(WidgetTester tester, PosReceipt receipt) =>
    tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: PosReceiptDialog(receipt: receipt)),
      ),
    );

void main() {
  testWidgets('an underpaid receipt shows the utang, not negative change', (
    tester,
  ) async {
    await _pump(tester, _receipt(paid: 1, total: 315));

    expect(find.text('Balance due (utang)'), findsOneWidget);
    expect(find.text('₱314.00'), findsOneWidget);
    expect(find.text('Change'), findsNothing);
    expect(find.textContaining('-₱'), findsNothing);
  });

  testWidgets('a fully paid receipt still shows the change', (tester) async {
    await _pump(tester, _receipt(paid: 500, total: 315));

    expect(find.text('Change'), findsOneWidget);
    expect(find.text('₱185.00'), findsOneWidget);
    expect(find.text('Balance due (utang)'), findsNothing);
  });

  testWidgets('the change is the SERVER\'s, not the till\'s own arithmetic', (
    tester,
  ) async {
    // QA High (Phase 4 close). Cash 240 + GCash 10 on a 225.00 sale: the server
    // decided this sale handed no change back, and the till has no business
    // recomputing one from the tender rows - it used to, and printed 0.00 for a
    // 15.00 change while the payment dialog previewed 15.00.
    await _pump(
      tester,
      PosReceipt(
        reference: 'TRX-20261111-0005',
        officialReceiptNumber: 'OR-20261111-0005',
        createdAt: DateTime(2026, 11, 11, 15, 25),
        lines: const [],
        paymentMethod: 'CASH',
        amountPaid: 250,
        total: 225,
        // Non-VAT, so the two VAT rows cannot also print a ₱0.00.
        vatRegistered: false,
        payments: const [
          PosReceiptPayment(method: 'CASH', amount: 240),
          PosReceiptPayment(method: 'GCASH', amount: 10),
        ],
      ),
    );

    expect(
      find.text('₱0.00'),
      findsOneWidget,
      reason: 'the server said this sale gave no change',
    );
    expect(
      find.text('₱5.00'),
      findsNothing,
      reason: '240 + 10 - 225 is not change the drawer paid out',
    );
  });

  testWidgets('the change printed is the server number, not paid minus total', (
    tester,
  ) async {
    // Built from the JSON `/transactions/` really answers with, so the parse and
    // the print are both covered. On a 225.00 sale tendered at 250 the till's own
    // arithmetic would print 25.00; the server says 12.50.
    final result = PosCheckoutResult.fromJson(const {
      'id': 38,
      'transaction_no': 'TRX-20261024-0038',
      'trans_date': '2026-10-24T12:00:00Z',
      'grand_total': '225.00',
      'change_given': '12.50',
      'receipt': {'or_number': 'OR-20261024-0038'},
    });
    expect(result.changeGiven, 12.5, reason: 'the server body carried it');

    await _pump(
      tester,
      PosReceipt(
        reference: result.transactionNo,
        officialReceiptNumber: result.orNumber,
        createdAt: result.transDate,
        lines: const [],
        paymentMethod: 'CASH',
        amountPaid: 250,
        changeGiven: result.changeGiven,
        total: result.grandTotal,
        // Non-VAT, so the VAT rows cannot also print a ₱0.00.
        vatRegistered: false,
      ),
    );

    expect(find.text('Change'), findsOneWidget);
    expect(
      find.text('₱12.50'),
      findsOneWidget,
      reason: 'the server decided how much left the drawer',
    );
    expect(
      find.text('₱25.00'),
      findsNothing,
      reason: '250 - 225 is arithmetic the till does not get to do',
    );
  });
}
