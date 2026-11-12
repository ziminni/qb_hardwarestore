// Phase 5 F4 (decision 18): the till line badge and the receipt's pick-up line.
//
// Two surfaces, one fact: where the shop keeps the goods. The badge is a PLACE,
// never a stock claim — "Bodega" says nothing about how many are left — and a
// legacy sale with no recorded place prints NO caption rather than an invented
// "Store".

import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_receipt_dialog.dart';
import 'package:client/features/pos/widgets/pos_transaction_cart.dart';
import 'package:client/features/pos/widgets/receipt_document.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

class _QuietPosRepository extends PosRepository {
  _QuietPosRepository() : super(PosService());

  @override
  Future<int> walkInCustomerId() async => 1;
}

/// A catalogue row that names a pick-up point, the way the server answers once
/// B4 is live.
PosCatalogItem _item({String storedAtName = 'Bodega'}) => PosCatalogItem(
  variantUomId: 1,
  variantId: 1,
  productName: 'Portland Cement',
  variantName: '40kg',
  unit: 'BAG',
  barcode: '',
  conversionFactor: 1,
  unitPrice: 270,
  availableBaseStock: 100,
  storedAtName: storedAtName,
);

PosReceipt _receipt({String storedAtName = 'Bodega'}) => PosReceipt(
  reference: 'TRX-20261112-0007',
  officialReceiptNumber: 'OR-20261112-0007',
  createdAt: DateTime(2026, 11, 12, 10),
  lines: [
    PosCartLine(
      variantUomId: 1,
      productName: 'Portland Cement',
      variantName: '40kg',
      quantity: 2,
      unit: 'BAG',
      unitPrice: 450,
      availableQuantity: 10,
      storedAtName: storedAtName,
    ),
  ],
  paymentMethod: 'CASH',
  amountPaid: 900,
  total: 900,
);

void main() {
  late InventoryViewmodel inventory;
  late PosTransactionViewmodel cart;

  setUp(() {
    inventory = seededInventory();
    cart = PosTransactionViewmodel(inventory, pos: _QuietPosRepository());
  });

  Future<void> pumpCart(WidgetTester tester) => tester.pumpWidget(
    ChangeNotifierProvider<PosTransactionViewmodel>.value(
      value: cart,
      child: MaterialApp(
        home: Scaffold(
          body: PosTransactionCart(
            onPayment: () {},
            onClear: () {},
            onChangeCustomer: () {},
          ),
        ),
      ),
    ),
  );

  testWidgets('a cart line badges the location from the catalogue', (
    tester,
  ) async {
    expect(cart.addLine(_item(), 2), isNull);
    await pumpCart(tester);

    expect(find.text('Bodega'), findsOneWidget);
    // A place, not a quantity claim: the line's own "20 BAG" is the quantity
    // stepper, and the badge must not add a second stock number.
    expect(find.byKey(const ValueKey('pos-cart-location-0')), findsOneWidget);
    expect(find.textContaining('in stock'), findsNothing);
    expect(find.textContaining('left'), findsNothing);
  });

  testWidgets('a row with no location shows no badge', (tester) async {
    expect(cart.addLine(_item(storedAtName: ''), 2), isNull);
    await pumpCart(tester);

    expect(find.byKey(const ValueKey('pos-cart-location-0')), findsNothing);
    expect(find.text('Bodega'), findsNothing);
  });

  group('the 80 mm receipt', () {
    test('prints "Pick up at" from the sale line', () {
      final content = ReceiptContent(_receipt());

      expect(content.lines.single.pickUp, 'Pick up at Bodega');
    });

    test('a legacy sale with no recorded place prints no caption', () {
      final content = ReceiptContent(_receipt(storedAtName: ''));

      expect(
        content.lines.single.pickUp,
        isNull,
        reason:
            'an invented "Store" would tell the customer to collect goods from '
            'somewhere nobody chose',
      );
    });
  });

  group('the on-screen receipt', () {
    testWidgets('shows the pick-up line under its item', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PosReceiptDialog(receipt: _receipt())),
        ),
      );

      expect(find.text('Pick up at Bodega'), findsOneWidget);
    });

    testWidgets('a sale with no recorded place shows no pick-up line', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosReceiptDialog(receipt: _receipt(storedAtName: '')),
          ),
        ),
      );

      expect(find.textContaining('Pick up at'), findsNothing);
    });
  });
}
