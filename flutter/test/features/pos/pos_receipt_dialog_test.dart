import 'package:client/data/models/pos_transaction.dart';
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
}
