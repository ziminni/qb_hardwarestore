// Phase 4 Task F4b (decision 18): a sale may take SEVERAL tenders.
//
// Three things are load-bearing here:
//   * every tender reaches `payments[]`: collapsing a split sale into one method
//     would tell the server money arrived in a drawer it never reached;
//   * the remaining balance is live, and the last row follows it while untouched;
//   * change comes from CASH only, because a cheque is not money the shop holds.

import 'package:client/data/models/tender_method.dart';
import 'package:client/features/pos/widgets/pos_payment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<PosPaymentDetails?> _open(
  WidgetTester tester, {
  double total = 20,
  bool customerIsNamed = true,
}) async {
  PosPaymentDetails? result;
  // The dialog is taller than the default 800x600 test window, and a row below the
  // fold cannot be tapped (the tap would land nowhere).
  tester.view.physicalSize = const Size(1400, 1800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showDialog<PosPaymentDetails>(
                context: context,
                builder: (_) => PosPaymentDialog(
                  total: total,
                  customerIsNamed: customerIsNamed,
                ),
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

void main() {
  testWidgets('a cash and GCash sale sends two tenders', (tester) async {
    await _open(tester);

    // First tender: 15 cash. Second: 5 GCash, which completes the 20.
    await tester.enterText(
      find.byKey(const ValueKey('pos-tender-amount-0')),
      '15',
    );
    await tester.tap(find.byKey(const ValueKey('pos-add-tender')));
    await tester.pumpAndSettle();
    await _setMethod(tester, 1, 'GCash');
    await tester.enterText(
      find.byKey(const ValueKey('pos-tender-amount-1')),
      '5',
    );
    await tester.pumpAndSettle();

    expect(find.text('Paid now'), findsOneWidget);
    // Nothing left owing, so no utang sentence.
    expect(find.textContaining('will be left unpaid'), findsNothing);

    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle();

    // The dialog closed and handed back BOTH tenders, in order.
    expect(find.text('Payment'), findsNothing);
  });

  testWidgets('a new tender row pre-fills what is still owed', (tester) async {
    await _open(tester, total: 20);

    await tester.enterText(
      find.byKey(const ValueKey('pos-tender-amount-0')),
      '12',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pos-add-tender')));
    await tester.pumpAndSettle();

    final second = tester.widget<TextFormField>(
      find.byKey(const ValueKey('pos-tender-amount-1')),
    );
    expect(
      second.controller?.text,
      '8.00',
      reason: '20 less the 12 already taken',
    );
  });

  testWidgets('a discount leaves the last untouched row showing what is owed', (
    tester,
  ) async {
    await _open(tester, total: 20);

    // 10 percent off 20 leaves 18 due, and the untouched cash row follows it.
    await tester.tap(find.text('% Percent'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('pos-discount-value')),
      '10',
    );
    await tester.enterText(
      find.byKey(const ValueKey('pos-discount-reason')),
      'loyal customer',
    );
    await tester.pumpAndSettle();

    expect(find.text('Amount due: ₱18.00'), findsOneWidget);
    final cash = tester.widget<TextFormField>(
      find.byKey(const ValueKey('pos-tender-amount-0')),
    );
    expect(cash.controller?.text, '18.00');
  });

  testWidgets('only cash produces change, and it is shown as such', (
    tester,
  ) async {
    await _open(tester, total: 20);

    await tester.enterText(
      find.byKey(const ValueKey('pos-tender-amount-0')),
      '25',
    );
    await tester.pumpAndSettle();

    expect(find.text('Change (cash only)'), findsOneWidget);
    expect(find.text('₱5.00'), findsOneWidget);
  });

  testWidgets('a row can be removed, but never the only one', (tester) async {
    await _open(tester);

    // With one row the remove button is disabled.
    final onlyRow = tester.widget<IconButton>(
      find.byKey(const ValueKey('pos-remove-tender-0')),
    );
    expect(onlyRow.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('pos-add-tender')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pos-remove-tender-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('pos-tender-amount-1')), findsNothing);
  });

  testWidgets('the dialog hands back every tender with its method', (
    tester,
  ) async {
    PosPaymentDetails? details;
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                details = await showDialog<PosPaymentDetails>(
                  context: context,
                  builder: (_) => const PosPaymentDialog(total: 20),
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
    await tester.enterText(
      find.byKey(const ValueKey('pos-tender-amount-0')),
      '15',
    );
    await tester.tap(find.byKey(const ValueKey('pos-add-tender')));
    await tester.pumpAndSettle();
    await _setMethod(tester, 1, 'GCash');
    await tester.enterText(
      find.byKey(const ValueKey('pos-tender-amount-1')),
      '5',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle();

    expect(details, isNotNull);
    expect(details!.tenders, hasLength(2));
    expect(details!.tenders[0].method, TenderMethod.cash);
    expect(details!.tenders[0].amount, 15);
    expect(details!.tenders[1].method, TenderMethod.gcash);
    expect(details!.tenders[1].amount, 5);
    expect(details!.paidNow, 20);
    expect(details!.pendingChequeTotal, 0);
  });

  testWidgets('a split sale that leaves a balance still warns about utang', (
    tester,
  ) async {
    await _open(tester, total: 20);

    await tester.enterText(
      find.byKey(const ValueKey('pos-tender-amount-0')),
      '12',
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('₱8.00 will be left unpaid'), findsOneWidget);
  });
}
