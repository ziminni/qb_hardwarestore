// Phase 4 task 6 (decision 14, locked decision 4), migrating the Phase 3 dialog to the
// three-way outcome the walk-in rule now requires.
//
// Phase 3's dialog assumed ANY underpaid sale could be charged to the Walk-in Customer. Task 2
// made the server refuse that: an anonymous sale cannot go into utang, because a balance on the
// shared placeholder is money owed by nobody. So the cashier needs a way OUT of that state, and
// this dialog is where they meet it.
//
// The pre-existing job is unchanged and still tested: submitting an underpaid sale makes the
// server post a `CollectibleLedger`, so this is the last point at which a typo is free. What
// changes is that "Go back" is no longer the only alternative to booking a debt.

import 'package:client/features/pos/widgets/pos_underpayment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Pumps and opens the dialog, then optionally taps one of its actions.
  ///
  /// The tap happens AFTER the open, not as a callback: `showDialog` does not complete until
  /// the dialog is dismissed, so anything that awaits it and then "taps" is dead code - which
  /// is exactly how the first version of this helper failed, in four tests at once.
  Future<PosUnderpaymentChoice?> show(
    WidgetTester tester, {
    required bool isAnonymous,
    String customerName = 'Maria Santos',
    String? tap,
  }) async {
    PosUnderpaymentChoice? answer;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  answer = await showDialog<PosUnderpaymentChoice>(
                    context: context,
                    builder: (_) => PosUnderpaymentDialog(
                      total: 750,
                      amountPaid: 500,
                      customerName: customerName,
                      isAnonymous: isAnonymous,
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
    if (tap != null) {
      await tester.tap(find.text(tap));
      await tester.pumpAndSettle();
    }
    return answer;
  }

  testWidgets('states the total, what was paid, and the shortfall', (
    tester,
  ) async {
    await show(tester, isAnonymous: false);

    expect(find.text('Total'), findsOneWidget);
    expect(find.text('750.00'), findsOneWidget);
    expect(find.text('Paid'), findsOneWidget);
    expect(find.text('500.00'), findsOneWidget);
    expect(find.text('250.00'), findsOneWidget, reason: '750 - 500');
  });

  group('a NAMED customer keeps the Phase 3 behaviour', () {
    testWidgets('offers to record the utang or go back', (tester) async {
      await show(tester, isAnonymous: false);

      expect(find.text('Record the utang'), findsOneWidget);
      expect(find.text('Go back'), findsOneWidget);
      expect(find.textContaining('Maria Santos'), findsOneWidget);
      expect(
        find.text(
          'This records a receivable against the customer. Nothing has been '
          'submitted yet.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('"Record the utang" answers recordUtang', (tester) async {
      final answer = await show(
        tester,
        isAnonymous: false,
        tap: 'Record the utang',
      );
      expect(answer, PosUnderpaymentChoice.recordUtang);
    });

    testWidgets('"Go back" answers NOTHING, so nothing is submitted', (
      tester,
    ) async {
      final answer = await show(tester, isAnonymous: false, tap: 'Go back');
      expect(
        answer,
        isNull,
        reason: 'null must not be read as "go ahead" - it submits nothing',
      );
    });
  });

  group('an ANONYMOUS sale cannot owe, so it is offered a way out', () {
    testWidgets('says the sale has no customer to owe the shortfall', (
      tester,
    ) async {
      await show(
        tester,
        isAnonymous: true,
        customerName: 'Walk-in Customer (anonymous)',
      );

      expect(
        find.textContaining('cannot go into utang'),
        findsOneWidget,
        reason:
            'the cashier must know WHY, not just that the button is missing',
      );
      // It must NOT promise a receivable, because none would be created.
      expect(
        find.textContaining('This records a receivable'),
        findsNothing,
        reason: 'that copy is a lie for an anonymous sale',
      );
    });

    testWidgets('offers both routes', (tester) async {
      await show(
        tester,
        isAnonymous: true,
        customerName: 'Walk-in Customer (anonymous)',
      );

      expect(find.text('Collect the full amount'), findsOneWidget);
      expect(find.text('Record a customer for this utang'), findsOneWidget);
      expect(
        find.text('Record the utang'),
        findsNothing,
        reason: 'there is no account to record it against yet',
      );
    });

    testWidgets('"Collect the full amount" answers collectFull', (
      tester,
    ) async {
      final answer = await show(
        tester,
        isAnonymous: true,
        customerName: 'Walk-in Customer (anonymous)',
        tap: 'Collect the full amount',
      );
      expect(answer, PosUnderpaymentChoice.collectFull);
    });

    testWidgets('"Record a customer for this utang" answers nameCustomer', (
      tester,
    ) async {
      final answer = await show(
        tester,
        isAnonymous: true,
        customerName: 'Walk-in Customer (anonymous)',
        tap: 'Record a customer for this utang',
      );
      expect(answer, PosUnderpaymentChoice.nameCustomer);
    });
  });
}
