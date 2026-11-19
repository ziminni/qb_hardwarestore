// Owner 2026-11-19: the till's payment dialog is a step flow: Items (only
// when the till passes its cart) → Payment + Delivery → Discount (skipped when
// the sale allows none) → Review. The old
// single "Complete sale" press is now Next … then "Complete transaction".
// One helper walks it, so a later change to the steps is fixed in one place.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The dialog's forward button: "Next" on early steps, "Complete transaction"
/// on the last. Present exactly while the payment dialog is open.
final Finder paymentNext = find.byKey(const ValueKey('pos-payment-next'));

Future<void> _tapNext(WidgetTester tester) async {
  await tester.ensureVisible(paymentNext);
  await tester.pumpAndSettle();
  await tester.tap(paymentNext);
  await tester.pumpAndSettle();
}

/// Presses Next until the last step, then "Complete transaction".
///
/// A step that refuses to move on (a validation error) keeps refusing on the
/// next press, so a test of a refusal still sees the dialog open with its
/// message after the walk (at most four presses).
Future<void> completePayment(WidgetTester tester) async {
  for (var press = 0; press < 4; press++) {
    if (paymentNext.evaluate().isEmpty) return; // the dialog closed
    final onLast = find
        .descendant(
          of: paymentNext,
          matching: find.text('Complete transaction'),
        )
        .evaluate()
        .isNotEmpty;
    await _tapNext(tester);
    if (onLast) return;
  }
}

/// Presses Next until [marker] is on screen (at most three presses).
Future<void> _nextUntil(WidgetTester tester, Finder marker) async {
  for (var press = 0; press < 3; press++) {
    if (marker.evaluate().isNotEmpty) return;
    await _tapNext(tester);
  }
}

/// On to the Payment step: past Items when the till passed its cart.
Future<void> goToPaymentStep(WidgetTester tester) =>
    _nextUntil(tester, find.byKey(const ValueKey('pos-tender-method-0')));

/// On to the Discount step.
Future<void> goToDiscountStep(WidgetTester tester) =>
    _nextUntil(tester, find.byKey(const ValueKey('pos-discount-toggle')));

/// On to the last step, Review (its button reads "Complete transaction").
Future<void> goToReviewStep(WidgetTester tester) => _nextUntil(
  tester,
  find.descendant(of: paymentNext, matching: find.text('Complete transaction')),
);
