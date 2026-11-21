// Goods the shop never discounts (owner ruling: cement, "Turn off for goods you
// never discount").
//
// The server refuses a line discount on such a product with 400 INVALID_DISCOUNT and
// leaves the line out of the sale discount's base. The till must therefore:
//  1. carry the flag from the catalogue onto the cart line (like the name and the
//     pick-up point, which use the same route);
//  2. not OFFER the line-discount control on that line, and say why;
//  3. refuse a line discount set on it through the viewmodel, not only through the UI;
//  4. measure a sale discount on the discountable lines only, so the preview matches
//     what the server charges.

import 'package:client/data/models/pos_transaction.dart';
import 'package:client/data/models/sale_discount.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_transaction_cart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

class _StubPosRepository extends PosRepository {
  _StubPosRepository() : super(PosService());
}

/// Cement (id 1, never discounted) beside pipe (id 2, discountable).
PosTransactionViewmodel _till() {
  final products = [
    product(
      id: 1,
      name: 'Portland Cement',
      categoryName: 'Cement',
      allowDiscount: false,
      variants: [
        variant(
          id: 1,
          productId: 1,
          name: '40kg',
          baseUomCode: 'BAG',
          sellingUoms: [
            variantUom(
              id: 1,
              variantId: 1,
              price: 270,
              uomId: 2,
              uomCode: 'BAG',
              uomName: 'Bag',
              isWhole: true,
            ),
          ],
        ),
      ],
    ),
    product(
      id: 2,
      name: 'PVC Pipe',
      categoryName: 'Plumbing',
      variants: [
        variant(
          id: 2,
          productId: 2,
          name: '1/2 inch',
          sellingUoms: [
            variantUom(id: 2, variantId: 2, price: 95, uomCode: 'PC'),
          ],
        ),
      ],
    ),
  ];
  final batches = [
    batch(id: 1, variantId: 1, qty: 100, cost: 235),
    batch(id: 2, variantId: 2, qty: 100, cost: 70),
  ];
  return PosTransactionViewmodel(
    InventoryViewmodel.seeded(
      catalogue: FakeProductsRepository(products: products, batches: batches),
      inventory: FakeInventoryRepository(),
      catalogueLists: FakeCatalogueRepository(),
      products: products,
      batches: batches,
      stockOnHand: onHandFromBatches(batches),
    ),
    pos: _StubPosRepository(),
  );
}

Future<void> _pumpCart(
  WidgetTester tester,
  PosTransactionViewmodel cart,
) async {
  tester.view.physicalSize = const Size(760, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<PosTransactionViewmodel>.value(
      value: cart,
      child: MaterialApp(
        home: Scaffold(
          body: PosTransactionCart(
            onPayment: () {},
            onClear: () {},
            onChangeCustomer: () {},
            onHold: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

PosCatalogItem _row(PosTransactionViewmodel cart, String name) =>
    cart.filteredProducts.singleWhere((item) => item.productName == name);

void main() {
  test('the catalogue row carries the product\'s allow_discount', () {
    final cart = _till();

    expect(_row(cart, 'Portland Cement').allowDiscount, isFalse);
    expect(_row(cart, 'PVC Pipe').allowDiscount, isTrue);
  });

  test('the cart line carries the flag, like the name and the location', () {
    final cart = _till();
    expect(cart.addLine(_row(cart, 'Portland Cement'), 2), isNull);

    expect(cart.lines.single.productName, 'Portland Cement');
    expect(cart.lines.single.allowDiscount, isFalse);
  });

  test('the viewmodel refuses a line discount on a never-discounted line', () {
    final cart = _till();
    expect(cart.addLine(_row(cart, 'Portland Cement'), 2), isNull);

    cart.setLineDiscount(
      0,
      const PosDiscount(
        kind: DiscountKind.amount,
        value: 40,
        reason: 'chipped bag',
      ),
    );

    expect(cart.lines.single.discount, isNull);
    expect(cart.lineDiscountTotal, 0);
    expect(cart.total, 540);
  });

  test('a discountable line beside it still takes one', () {
    final cart = _till();
    expect(cart.addLine(_row(cart, 'Portland Cement'), 2), isNull);
    expect(cart.addLine(_row(cart, 'PVC Pipe'), 1), isNull);

    cart.setLineDiscount(
      1,
      const PosDiscount(
        kind: DiscountKind.amount,
        value: 5,
        reason: 'bulk',
      ),
    );

    expect(cart.lines.last.discount, isNotNull);
    expect(cart.lineDiscountTotal, 5);
  });

  test('the sale-discount base leaves the never-discounted lines out', () {
    final cart = _till();
    expect(cart.addLine(_row(cart, 'Portland Cement'), 2), isNull);
    expect(cart.addLine(_row(cart, 'PVC Pipe'), 2), isNull);

    // 540 of cement is never discounted; only 190 of pipe is.
    expect(cart.neverDiscountedTotal, 540);
    expect(cart.total, 730);

    final amounts = PosDiscountAmounts.forDiscount(
      cart.total,
      const PosDiscount(
        kind: DiscountKind.percent,
        value: 10,
        reason: 'loyal',
      ),
      lineDiscountAmount: cart.lineDiscountTotal,
      neverDiscountedTotal: cart.neverDiscountedTotal,
    );

    expect(amounts.discountAmount, 19, reason: '10% of the discountable 190');
    expect(amounts.gross, 730);
    expect(amounts.net, 711);
  });

  testWidgets('the cart does not offer a line discount on that line', (
    tester,
  ) async {
    final cart = _till();
    expect(cart.addLine(_row(cart, 'Portland Cement'), 2), isNull);
    await _pumpCart(tester, cart);

    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('pos-line-discount-open-0')),
    );

    expect(button.onPressed, isNull, reason: 'nothing to press');
    expect(button.tooltip, 'This product is never discounted');
  });

  testWidgets('a discountable line beside it keeps its control', (
    tester,
  ) async {
    final cart = _till();
    expect(cart.addLine(_row(cart, 'Portland Cement'), 2), isNull);
    expect(cart.addLine(_row(cart, 'PVC Pipe'), 1), isNull);
    await _pumpCart(tester, cart);

    final cement = tester.widget<IconButton>(
      find.byKey(const ValueKey('pos-line-discount-open-0')),
    );
    final pipe = tester.widget<IconButton>(
      find.byKey(const ValueKey('pos-line-discount-open-1')),
    );

    expect(cement.onPressed, isNull);
    expect(pipe.onPressed, isNotNull);
    expect(pipe.tooltip, 'Discount PVC Pipe');
  });
}
