// Phase 3 Task 5 (decision 06, section 4): the underpayment confirmation.
//
// Submitting an underpaid sale makes the server post a CollectibleLedger, so an
// accidental underpayment becomes a real debt on a real account, discovered only when
// the receipt prints. This dialog is the last point at which a typo is still free.
//
// The behaviour that matters is the RETURN VALUE: true submits, false submits nothing
// and leaves the cart alone. A dialog that always returned true (or was dismissed into
// a submit) would silently create the utang it exists to prevent.

import 'package:client/features/pos/widgets/pos_underpayment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<bool?> show(WidgetTester tester, {VoidCallback? onShown}) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  answer = await showDialog<bool>(
                    context: context,
                    builder: (_) => const PosUnderpaymentDialog(
                      total: 750,
                      amountPaid: 500,
                      customerName: 'Walk-in Customer',
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    onShown?.call();
    return answer;
  }

  testWidgets('states the total, what was paid, and the shortfall', (
    tester,
  ) async {
    await show(tester);

    expect(find.text('Total'), findsOneWidget);
    expect(find.text('750.00'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('500.00'), findsOneWidget);
    expect(find.text('To utang'), findsOneWidget);
    expect(find.text('250.00'), findsOneWidget, reason: '750 - 500');
    expect(find.textContaining('Walk-in Customer'), findsOneWidget);
  });

  testWidgets('submits NOTHING until the utang is accepted', (tester) async {
    // The wording is deliberate: nothing has been submitted at this point.
    await show(tester);
    expect(
      find.textContaining('Nothing has been submitted yet'),
      findsOneWidget,
    );
    expect(find.text('Record the utang'), findsOneWidget);
    expect(find.text('Go back'), findsOneWidget);
  });

  testWidgets('"Record the utang" answers true', (tester) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                answer = await showDialog<bool>(
                  context: context,
                  builder: (_) => const PosUnderpaymentDialog(
                    total: 750,
                    amountPaid: 500,
                    customerName: 'Walk-in Customer',
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

    await tester.tap(find.text('Record the utang'));
    await tester.pumpAndSettle();

    expect(answer, isTrue);
  });

  testWidgets('"Go back" answers FALSE, so nothing is submitted', (
    tester,
  ) async {
    bool? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () async {
                answer = await showDialog<bool>(
                  context: context,
                  builder: (_) => const PosUnderpaymentDialog(
                    total: 750,
                    amountPaid: 500,
                    customerName: 'Walk-in Customer',
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

    await tester.tap(find.text('Go back'));
    await tester.pumpAndSettle();

    expect(answer, isFalse, reason: 'false must not be read as "go ahead"');
  });
}
