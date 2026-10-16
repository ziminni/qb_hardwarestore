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

import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InventoryViewmodel inventory;
  late PosTransactionViewmodel cart;

  setUp(() {
    inventory = InventoryViewmodel();
    cart = PosTransactionViewmodel(inventory, ProductTrackingViewmodel());
  });

  /// Add a line, then drain that variant to zero so its catalogue row disappears.
  ({String product, String variant}) addThenDrain() {
    final product = cart.filteredProducts.first;
    final option = cart.saleOptionsFor(product).first;
    expect(cart.addLine(option, 1), isNull);
    final name = (product: option.productName, variant: option.variantName);
    inventory.sellStock(
      variantId: option.variantId,
      quantity: inventory.stockOnHandFor(option.variantId),
      reference: 'DRAIN',
      userName: 'Test',
    );
    expect(
      cart.saleOptionsFor(product),
      isEmpty,
      reason: 'the row must really be gone, or this test proves nothing',
    );
    return name;
  }

  test('a stale line is REPORTED, not thrown on', () {
    final names = addThenDrain();

    final error = cart.validate();

    expect(
      error,
      isNotNull,
      reason: 'the sale must be refused, not silently priced',
    );
    expect(error, contains(names.product));
    expect(error!.toLowerCase(), contains('remove'));
  });

  test('adding another line with a stale one present does not crash', () {
    addThenDrain();
    final other = cart.filteredProducts.first;
    final option = cart.saleOptionsFor(other).first;

    // Reserved-stock arithmetic walks every existing line, so it used to hit the dead
    // one and throw before it ever looked at the new line.
    expect(() => cart.addLine(option, 1), returnsNormally);
  });

  test('draining a variant does NOT crash the catalogue rebuild', () {
    addThenDrain();
    expect(() => cart.filteredProducts, returnsNormally);
    expect(() => cart.saleOptionsFor(cart.filteredProducts.first), returnsNormally);
  });
}
