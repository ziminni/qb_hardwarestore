// Phase 2 (2026-11-22): discount exclusions are chosen by the cashier at the till
// rather than blocked by a product-level flag. Any line can take a per-product
// discount, and when a whole-sale discount is used, unticking a line leaves it out
// of the measured base (`neverDiscountedTotal`).

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

/// Cement (id 1, legacy allowDiscount=false) beside pipe (id 2).
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
  test('a line discount is allowed even when legacy allowDiscount is false', () {
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

    expect(cart.lines.single.discount, isNotNull);
    expect(cart.lineDiscountTotal, 40);
    expect(cart.total, 500);
  });

  test('unticking a line leaves it out of the whole-sale discount base', () {
    final cart = _till();
    expect(cart.addLine(_row(cart, 'Portland Cement'), 2), isNull);
    expect(cart.addLine(_row(cart, 'PVC Pipe'), 2), isNull);

    // By default all lines are included in a whole-sale discount.
    expect(cart.neverDiscountedTotal, 0);

    // Cashier unticks Portland Cement (540); only PVC Pipe (190) is included.
    cart.setLineIncludedInDiscount(0, false);
    expect(cart.neverDiscountedTotal, 540);
    expect(cart.total, 730);

    final amounts = PosDiscountAmounts.forDiscount(
      cart.total,
      const PosDiscount(kind: DiscountKind.percent, value: 10, reason: 'bulk'),
      neverDiscountedTotal: cart.neverDiscountedTotal,
    );
    expect(amounts.discountAmount, 19);
    expect(amounts.net, 711);
  });

  testWidgets('cart offers line discount on every line by default', (
    tester,
  ) async {
    final cart = _till();
    expect(cart.addLine(_row(cart, 'Portland Cement'), 2), isNull);
    expect(cart.addLine(_row(cart, 'PVC Pipe'), 1), isNull);

    await _pumpCart(tester, cart);

    final cementBtn = tester.widget<IconButton>(
      find.byKey(const ValueKey('pos-line-discount-open-0')),
    );
    final pipeBtn = tester.widget<IconButton>(
      find.byKey(const ValueKey('pos-line-discount-open-1')),
    );
    expect(cementBtn.onPressed, isNotNull);
    expect(pipeBtn.onPressed, isNotNull);
  });
}
