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
import 'package:flutter_test/flutter_test.dart';

Future<PosPaymentDetails?> _open(
  WidgetTester tester, {
  double total = 1000,
}) async {
  PosPaymentDetails? result;
  await tester.pumpWidget(
    MaterialApp(
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

Future<void> _discountPercent(WidgetTester tester, String percent) async {
  // The Deliver section grows the dialog, so the discount controls can sit below
  // the fold of a test window: scroll to them the way the cashier would.
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

    await tester.tap(find.text('Complete sale'));
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
    await _toggleDeliver(tester);
    await _discountPercent(tester, '10');
    await _enterDelivery(tester, fee: '50');

    // 1000 gross less 100 (10%) is 900 goods + 50 delivery: the fee was not
    // reduced to 45, and it was not discounted away.
    expect(find.text('Amount due: ${formatPeso(950)}'), findsOneWidget);
    expect(find.text('Delivery charge'), findsOneWidget);
    expect(find.text(formatPeso(50)), findsWidgets);

    // The cashier tenders the full 1000 in cash: the change is measured on the
    // goods net PLUS the charge, so it is 50, not 100.
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

    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle();

    expect(
      find.text('The delivery fee needs at most two decimals.'),
      findsOneWidget,
      reason: 'the server refuses 10.005 rather than rounding it',
    );
  });

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

      await tester.tap(find.text('Complete sale'));
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
    await tester.tap(find.text('Complete sale'));
    await tester.pumpAndSettle();

    expect(details!.delivery, isNull);
  });
}
