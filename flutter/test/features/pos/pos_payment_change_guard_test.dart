// QA High (Phase 4 close): change is paid from the DRAWER, so a tender set whose
// change exceeds the cash taken is refused.
//
// The server decides this (`PAYMENT_EXCEEDS_TOTAL`); these pin the till's matching
// preview, so the cashier is told before a round trip - and that a legitimate
// cash+gCash split with change still goes through.

import 'package:client/features/pos/widgets/pos_payment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<PosPaymentDetails?> _open(
  WidgetTester tester, {
  double total = 225,
}) async {
  // A tall window: the dialog grows with every tender row, and a 600px test
  // surface pushes the "Add tender" button off it.
  tester.view.physicalSize = const Size(1200, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  PosPaymentDetails? result;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showDialog<PosPaymentDetails>(
                context: context,
                builder: (_) => PosPaymentDialog(total: total),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _setMethod(WidgetTester tester, int row, String label) async {
  await tester.tap(find.byKey(ValueKey('pos-tender-method-$row')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> _setAmount(WidgetTester tester, int row, String amount) async {
  await tester.enterText(
    find.byKey(ValueKey('pos-tender-amount-$row')),
    amount,
  );
  await tester.pump();
}

void main() {
  testWidgets('a GCash amount above the total is blocked before submit', (
    tester,
  ) async {
    await _open(tester);
    await _setMethod(tester, 0, 'GCash');
    await _setAmount(tester, 0, '240');

    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('lower the card or GCash amount'),
      findsOneWidget,
      reason: 'the drawer cannot pay back money that went to a wallet',
    );
    expect(
      find.text('Complete sale'),
      findsOneWidget,
      reason: 'the dialog stays open so the cashier can fix the amount',
    );
  });

  testWidgets('cash plus GCash with change from the cash still goes through', (
    tester,
  ) async {
    await _open(tester);
    await _setAmount(tester, 0, '230');
    await tester.tap(find.byKey(const ValueKey('pos-add-tender')));
    await tester.pumpAndSettle();
    await _setMethod(tester, 1, 'GCash');
    await _setAmount(tester, 1, '10');

    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle();

    expect(
      find.text('Complete sale'),
      findsNothing,
      reason: 'a valid split sale closes the dialog and hands the tenders back',
    );
  });
}
