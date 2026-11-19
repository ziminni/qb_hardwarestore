// Phase 5 F3 (decision 18): the Deliver section of the payment dialog.
//
// A delivery fee is NOT goods: it is added AFTER the discount and is never
// discounted, so a percent taken off the goods cannot eat the trip. The screen
// must ask for that money, and the wire must receive every field the server
// insists on.

import 'package:client/core/format/format.dart';
import 'package:client/data/models/delivery.dart';
import 'package:client/features/pos/widgets/pos_payment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../support/payment_steps.dart';

Future<PosPaymentDetails?> _open(
  WidgetTester tester, {
  double total = 1000,
  Size size = const Size(1400, 1100),
  double scale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  PosPaymentDetails? result;
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                result = await showDialog<PosPaymentDetails>(
                  context: context,
                  builder: (_) => PosPaymentDialog(total: total),
                );
              },
              child: const Text('Pay'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Pay'));
  await tester.pumpAndSettle();
  return result;
}

Future<void> _toggleDeliver(WidgetTester tester) async {
  // Below the Payment section on step 1: scroll to it like the cashier would.
  await tester.ensureVisible(find.byKey(const ValueKey('pos-deliver-toggle')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('pos-deliver-toggle')));
  await tester.pumpAndSettle();
}

Future<void> _enterDelivery(
  WidgetTester tester, {
  String fee = '50',
  String address = '12 Mabini St, Cebu City',
}) async {
  await tester.enterText(
    find.byKey(const ValueKey('pos-delivery-address')),
    address,
  );
  await tester.enterText(
    find.byKey(const ValueKey('pos-delivery-contact')),
    'Maria Santos',
  );
  await tester.enterText(
    find.byKey(const ValueKey('pos-delivery-phone')),
    '09171234567',
  );
  await tester.enterText(find.byKey(const ValueKey('pos-delivery-fee')), fee);
  await tester.pumpAndSettle();
}

/// Owner 2026-11-19: the discount is behind an off-by-default switch, like
/// Deliver; its fields appear once it is on.
Future<void> _discountOn(WidgetTester tester) async {
  await goToDiscountStep(tester);
  final toggle = find.byKey(const ValueKey('pos-discount-toggle'));
  await tester.ensureVisible(toggle);
  await tester.pumpAndSettle();
  await tester.tap(toggle);
  await tester.pumpAndSettle();
}

Future<void> _discountPercent(WidgetTester tester, String percent) async {
  // The Deliver section grows the dialog, so the discount controls can sit below
  // the fold of a test window: scroll to them the way the cashier would.
  await _discountOn(tester);
  await tester.ensureVisible(find.text('% Percent'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('% Percent'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey('pos-discount-value')),
    percent,
  );
  await tester.enterText(
    find.byKey(const ValueKey('pos-discount-reason')),
    'bulk order',
  );
  await tester.pumpAndSettle();
}

// Every required sentence must be readable whole: a clipped error tells the
// cashier nothing. Names the clipped ones in the failure.
void _expectFullErrors(WidgetTester tester, List<String> messages) {
  final clipped = <String>[];
  for (final message in messages) {
    final error = find.text(message);
    expect(error, findsOneWidget);
    if (tester.renderObject<RenderParagraph>(error).didExceedMaxLines) {
      clipped.add(message);
    }
  }
  expect(clipped, isEmpty, reason: 'these errors are clipped: $clipped');
}

void _expectDeliveryErrorsFull(WidgetTester tester) =>
    _expectFullErrors(tester, const [
      'A delivery needs an address.',
      'A delivery needs a contact name.',
      'A delivery needs a contact phone number.',
    ]);

void main() {
  testWidgets('Deliver reveals the four fields, pre-dated for tomorrow', (
    tester,
  ) async {
    await _open(tester);
    expect(
      find.byKey(const ValueKey('pos-delivery-address')),
      findsNothing,
      reason: 'a carried-out sale must not show delivery fields',
    );

    await _toggleDeliver(tester);

    expect(find.byKey(const ValueKey('pos-delivery-address')), findsOneWidget);
    expect(find.byKey(const ValueKey('pos-delivery-contact')), findsOneWidget);
    expect(find.byKey(const ValueKey('pos-delivery-phone')), findsOneWidget);
    expect(find.byKey(const ValueKey('pos-delivery-fee')), findsOneWidget);
    final now = DateTime.now();
    expect(
      find.text(formatDate(DateTime(now.year, now.month, now.day + 1))),
      findsOneWidget,
      reason: 'a delivery is arranged ahead; today would claim it has left',
    );
  });

  testWidgets('an incomplete delivery is refused with a sentence per field', (
    tester,
  ) async {
    await _open(tester);
    await _toggleDeliver(tester);

    await completePayment(tester);
    await tester.pumpAndSettle();

    expect(find.text('A delivery needs an address.'), findsOneWidget);
    expect(find.text('A delivery needs a contact name.'), findsOneWidget);
    expect(
      find.text('A delivery needs a contact phone number.'),
      findsOneWidget,
    );
  });

  testWidgets('the fee is added AFTER the discount and is never discounted', (
    tester,
  ) async {
    await _open(tester);
    // Step 1 holds the delivery; Next refuses to leave it half filled in, so
    // the details go in before moving on to the discount (step 2).
    await _toggleDeliver(tester);
    await _enterDelivery(tester, fee: '50');
    await _discountPercent(tester, '10');

    // 1000 gross less 100 (10%) is 900 goods + 50 delivery: the fee was not
    // reduced to 45, and it was not discounted away.
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('pos-amount-due'))).data,
      formatPeso(950),
    );
    // The Review step itemises the charge on its own row.
    await goToReviewStep(tester);
    expect(find.text('Delivery charge'), findsOneWidget);
    expect(find.text(formatPeso(50)), findsWidgets);

    // The cashier tenders the full 1000 in cash (back on the Payment step,
    // two back): the change is measured on the goods net PLUS the charge, so
    // it is 50, not 100.
    for (var back = 0; back < 2; back++) {
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.byKey(const ValueKey('pos-tender-amount-0')),
      '1000',
    );
    await tester.pumpAndSettle();
    expect(find.text(formatPeso(50)), findsWidgets);
    expect(
      find.text(formatPeso(100)),
      findsNothing,
      reason: 'a 100 change would mean the trip was never charged',
    );
  });

  testWidgets('a fee with three decimals is refused before the round trip', (
    tester,
  ) async {
    await _open(tester);
    await _toggleDeliver(tester);
    await _enterDelivery(tester, fee: '10.005');

    await completePayment(tester);
    await tester.pumpAndSettle();

    expect(
      find.text('The delivery fee needs at most two decimals.'),
      findsOneWidget,
      reason: 'the server refuses 10.005 rather than rounding it',
    );
  });

  testWidgets('the fee error renders in full at 760 px and 1.3x text', (
    tester,
  ) async {
    // Item 15: the fee sits in a half-width column beside the date button, so its
    // longest refusal used to ellipsize to one line.
    await _open(tester, size: const Size(760, 1000), scale: 1.3);
    await _toggleDeliver(tester);
    await _enterDelivery(tester, fee: 'ten');

    await completePayment(tester);
    await tester.pumpAndSettle();

    final error = find.text('The delivery fee must be a number, 0 or more.');
    expect(error, findsOneWidget);
    final paragraph = tester.renderObject<RenderParagraph>(error);
    expect(
      paragraph.didExceedMaxLines,
      isFalse,
      reason: 'a clipped error cannot be read or acted on',
    );
  });

  testWidgets('each required delivery error renders in full at 760 px', (
    tester,
  ) async {
    // QA Low cosmetic: the phone shares a half-width row with the contact name,
    // so its longest refusal used to ellipsize to one line.
    await _open(tester, size: const Size(760, 1000));
    await _toggleDeliver(tester);

    await completePayment(tester);
    await tester.pumpAndSettle();

    _expectDeliveryErrorsFull(tester);
  });

  testWidgets(
    'each required delivery error renders in full at 760 px and 1.3x text',
    (tester) async {
      await _open(tester, size: const Size(760, 1000), scale: 1.3);
      await _toggleDeliver(tester);

      await completePayment(tester);
      await tester.pumpAndSettle();

      _expectDeliveryErrorsFull(tester);
    },
  );

  testWidgets(
    'completing hands back the delivery exactly as the wire wants it',
    (tester) async {
      PosPaymentDetails? details;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    details = await showDialog<PosPaymentDetails>(
                      context: context,
                      builder: (_) => const PosPaymentDialog(total: 1000),
                    );
                  },
                  child: const Text('Pay'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Pay'));
      await tester.pumpAndSettle();
      await _toggleDeliver(tester);
      await _enterDelivery(tester);

      await completePayment(tester);
      await tester.pumpAndSettle();

      final draft = details!.delivery;
      expect(draft, isNotNull);
      final now = DateTime.now();
      expect(draft!.toJson(), {
        'address': '12 Mabini St, Cebu City',
        'contact_name': 'Maria Santos',
        'contact_phone': '09171234567',
        'scheduled_date': DeliveryDraft.wireDate(
          DateTime(now.year, now.month, now.day + 1),
        ),
        'fee': '50.00',
      });
    },
  );

  testWidgets('a carried-out sale sends no delivery at all', (tester) async {
    PosPaymentDetails? details;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  details = await showDialog<PosPaymentDetails>(
                    context: context,
                    builder: (_) => const PosPaymentDialog(total: 1000),
                  );
                },
                child: const Text('Pay'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();
    await completePayment(tester);
    await tester.pumpAndSettle();

    expect(details!.delivery, isNull);
  });
}
