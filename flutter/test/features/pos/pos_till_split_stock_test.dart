// Phase 9 F1 (decision 21 §5): the till's availability is the TOTAL across
// shelves, because a sale draws from all of them (home first, then the others).
//
// The batches are still there for COST, so a store answers both lists. These
// tests arrange them to disagree on purpose: the lots say 130, the server's
// on-hand read says 3 at Store and 2 at Bodega. Availability has to be 5 — the
// number the cashier may actually sell — not the batch sum.

import 'package:client/data/models/stock_on_hand.dart';
import 'package:client/data/repositories/pos_repository.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

/// A cupboard stocked on two shelves, with a decoy lot worth 130.
InventoryViewmodel _splitStore() => InventoryViewmodel.seeded(
  catalogue: FakeProductsRepository(
    products: seededProducts(),
    batches: [batch(id: 1, variantId: 1, qty: 130, cost: 235)],
  ),
  inventory: FakeInventoryRepository(),
  catalogueLists: FakeCatalogueRepository(),
  products: seededProducts(),
  batches: [batch(id: 1, variantId: 1, qty: 130, cost: 235)],
  stockOnHand: const [
    StockOnHand(
      variantId: 1,
      locationId: 1,
      locationName: 'Store',
      locationActive: true,
      isHome: true,
      qty: 3,
    ),
    StockOnHand(
      variantId: 1,
      locationId: 2,
      locationName: 'Bodega',
      locationActive: true,
      isHome: false,
      qty: 2,
    ),
  ],
);

void main() {
  test('availability is the total across shelves, not one shelf', () {
    final till = PosTransactionViewmodel(
      _splitStore(),
      pos: PosRepository(PosService()),
    );

    final row = till.filteredProducts.singleWhere(
      (item) => item.variantId == 1,
    );

    // 3 + 2, and NOT the 130 the decoy lot claims.
    expect(row.availableBaseStock, 5);
    expect(row.availableSaleQuantity, 5, reason: 'one BAG is one base unit');
  });

  test('a cart beyond the total is refused, so no shelf is over-promised', () {
    final till = PosTransactionViewmodel(
      _splitStore(),
      pos: PosRepository(PosService()),
    );

    final error = till.addLine(
      till.filteredProducts.singleWhere((item) => item.variantId == 1),
      6,
    );

    expect(error, contains('Only 5 BAG available'));
    expect(till.lines, isEmpty);
  });
}
