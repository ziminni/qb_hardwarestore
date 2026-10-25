// Phase 3 final-review fix. Found by the review's adversarial pass, then reproduced:
//
//   ADDED variant=1 uom=1
//   STOCK NOW 0.0
//   ROWS FOR VARIANT NOW 0
//   RESULT CRASH: StateError: Bad state: No element
//
// The catalogue is a GETTER rebuilt from live stock, and it SKIPS any variant whose
// stock has reached 0. A cart line can outlive that: a server refresh (`load()`), or a
// sale on another screen sharing the same InventoryViewmodel, can take a variant to
// zero while a line for it still sits in the basket. The cart then looked its line up
// with `firstWhere` and no `orElse`, so the lookup threw and the POS crashed.
//
// The right behaviour is not to ignore the line - that would price and POST a sale for
// a product the catalogue says cannot be sold - but to tell the cashier, by name, to
// remove it.
//
// Phase 4 Task 4: the drain is now a RELOAD (the fake repository answering zero stock),
// which is exactly how it happens in production — the local `sellStock` that used to
// drain it was deleted with the rest of the in-memory mutations.

import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

void main() {
  late FakeProductsRepository products;
  late InventoryViewmodel inventory;
  late PosTransactionViewmodel cart;

  List<dynamic> catalogueRows() => [
    product(
      id: 1,
      name: 'Circuit Breaker',
      variants: [variant(id: 1, productId: 1, name: '20A 1-pole')],
    ),
  ];

  Future<void> pumpStock(double qty) async {
    products = FakeProductsRepository(
      products: catalogueRows().cast(),
      batches: qty > 0 ? [batch(id: 1, variantId: 1, qty: qty)] : const [],
    );
    inventory = InventoryViewmodel(
      products: products,
      inventory: FakeInventoryRepository(),
      catalogue: FakeCatalogueRepository(),
    );
    await inventory.load();
    cart = PosTransactionViewmodel(inventory, ProductTrackingViewmodel());
  }

  /// Add a line, then RELOAD the catalogue with the variant at zero so its row
  /// disappears while the line stays in the basket.
  Future<({String product, String variant})> addThenDrain() async {
    final productRow = cart.filteredProducts.first;
    final option = cart.saleOptionsFor(productRow).first;
    expect(cart.addLine(option, 1), isNull);
    final name = (product: option.productName, variant: option.variantName);

    products.setSnapshot(products: catalogueRows().cast(), batches: const []);
    await inventory.load();

    expect(
      cart.saleOptionsFor(productRow),
      isEmpty,
      reason: 'the row must really be gone, or this test proves nothing',
    );
    return name;
  }

  test('a stale line is REPORTED, not thrown on', () async {
    await pumpStock(5);

    final names = await addThenDrain();
    final error = cart.validate();

    expect(
      error,
      isNotNull,
      reason: 'the sale must be refused, not silently priced',
    );
    expect(error, contains(names.product));
    expect(error!.toLowerCase(), contains('remove'));
  });

  test('adding another line with a stale one present does not crash', () async {
    await pumpStock(5);
    await addThenDrain();

    // Reserved-stock arithmetic walks every existing line, so it used to hit the dead
    // one and throw before it ever looked at the new line.
    expect(() => cart.filteredProducts, returnsNormally);
  });

  test('draining a variant does NOT crash the catalogue rebuild', () async {
    await pumpStock(5);
    await addThenDrain();

    expect(() => cart.filteredProducts, returnsNormally);
  });
}
