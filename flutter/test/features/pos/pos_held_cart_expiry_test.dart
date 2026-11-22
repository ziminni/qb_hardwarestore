import 'package:client/data/models/held_cart.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/store_settings.dart';
import 'package:client/features/pos/widgets/pos_held_cart_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('StoreSettings parses and serializes held_cart_expiry_minutes', () {
    final settings = StoreSettings.fromJson({
      'vat_registered': true,
      'vat_rate': '12.00',
      'discount_cap_percent': '10.00',
      'held_cart_expiry_minutes': 90,
      'tender_fees': [],
    });
    expect(settings.heldCartExpiryMinutes, 90);
    expect(settings.toPatchJson()['held_cart_expiry_minutes'], 90);
  });

  test('TransactionLineItem parses fifo_batches in FIFO order', () {
    final item = TransactionLineItem.fromJson({
      'variant_uom': 1,
      'variant_uom_code': 'BAG',
      'qty': '5.00',
      'unit_price': '270.00',
      'subtotal': '1350.00',
      'fifo_batches': [
        {
          'batch_id': 11,
          'received_at': '2026-11-01T08:00:00Z',
          'location_name': 'Store',
          'qty': '3.00',
          'unit_cost': '220.00',
        },
        {
          'batch_id': 12,
          'received_at': '2026-11-10T08:00:00Z',
          'location_name': 'Bodega',
          'qty': '2.00',
          'unit_cost': '230.00',
        },
      ],
    });
    expect(item.fifoBatches.length, 2);
    expect(item.fifoBatches[0].batchId, 11);
    expect(item.fifoBatches[0].qty, 3.0);
    expect(item.fifoBatches[0].locationName, 'Store');
    expect(item.fifoBatches[1].batchId, 12);
    expect(item.fifoBatches[1].unitCost, 230.0);
  });

  testWidgets('PosHeldCartCard shows active stock reservation and expired states', (
    tester,
  ) async {
    final activeCart = HeldCart(
      id: 1,
      customerId: null,
      customerName: 'Maria',
      cashierName: 'Ana',
      notes: '',
      items: const [
        HeldCartItem(id: 1, variantUom: 1, qty: 2, unitPrice: 100),
      ],
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(minutes: 45)),
      isExpired: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosHeldCartCard(
            cart: activeCart,
            ageLabel: '1 min ago',
            onResume: () {},
            onVoid: () {},
          ),
        ),
      ),
    );
    expect(find.textContaining('Stock reserved'), findsOneWidget);

    final expiredCart = HeldCart(
      id: 2,
      customerId: null,
      customerName: 'Pedro',
      cashierName: 'Ana',
      notes: '',
      items: const [
        HeldCartItem(id: 2, variantUom: 1, qty: 1, unitPrice: 100),
      ],
      createdAt: DateTime.now().subtract(const Duration(hours: 3)),
      expiresAt: DateTime.now().subtract(const Duration(minutes: 5)),
      isExpired: true,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PosHeldCartCard(
            cart: expiredCart,
            ageLabel: '3 hr ago',
            onResume: () {},
            onVoid: () {},
          ),
        ),
      ),
    );
    expect(find.text('Reservation expired · stock released'), findsOneWidget);
  });
}
