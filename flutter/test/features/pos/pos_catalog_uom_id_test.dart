// Phase 3 Task 1 (decision 06, section 2 landmine): cart lines must be keyed by a
// REAL VariantUom id.
//
// The API does `SalesItem.objects.create(variant_uom_id=item_id)` and then resolves
// `VariantUOM.objects.filter(pk=item_id)` to find the variant to deduct stock from.
// So the payload's `variant_id` is a VariantUOM id despite its name.
//
// The cart used to synthesize `record.variant.id * 100 + index`. For the mock's
// variant 1 that is 100, while its real selling unit is id 1 — so the assertion
// below fails today for a concrete, checkable reason rather than a vague one, and a
// synthetic id would have made the server deduct from the wrong unit or none.

import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import '../../support/phase4_fakes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InventoryViewmodel inventory;
  late PosTransactionViewmodel cart;

  setUp(() {
    inventory = seededInventory();
    cart = PosTransactionViewmodel(inventory);
  });

  test('every catalogue item carries a REAL selling-unit id', () {
    final products = cart.filteredProducts;

    expect(
      products,
      isNotEmpty,
      reason: 'the mock catalogue should offer something to sell',
    );

    for (final product in products) {
      final variant = inventory.variantFor(product.variantId);
      expect(variant, isNotNull);

      final realIds = variant!.sellingUoms.map((uom) => uom.id).toSet();
      for (final option in cart.saleOptionsFor(product)) {
        expect(
          realIds,
          contains(option.variantUomId),
          reason:
              '${option.productName} / ${option.unit} carries variantUomId '
              '${option.variantUomId}, which is not one of the variant\'s real '
              'selling-unit ids $realIds. The API resolves this field as a '
              'VariantUOM id, so a synthetic value targets the wrong unit.',
        );
      }
    }
  });

  test('the base unit maps to the selling unit matching the base uom code', () {
    final product = cart.filteredProducts.firstWhere(
      (item) => item.variantId == 1,
    );
    final variant = inventory.variantFor(1)!;
    // The mock seeds variant 1 with a single selling unit whose code is 'Bag' and
    // whose id is 1 — deliberately not 100, which is what `id * 100 + index` gave.
    final expected = variant.sellingUoms
        .firstWhere((uom) => uom.uomCode == variant.baseUomCode)
        .id;

    final option = cart
        .saleOptionsFor(product)
        .firstWhere((item) => item.unit == variant.baseUomCode);

    expect(option.variantUomId, expected);
    expect(option.variantUomId, 1);
  });

  test('two variants do not collide on the same unit id', () {
    // The synthesized scheme (`variantId * 100 + index`) could not collide, but a
    // naive fix could: rows must be identified by the selling unit, not the variant.
    final products = cart.filteredProducts;
    final keys = <String>[];
    for (final product in products) {
      for (final option in cart.saleOptionsFor(product)) {
        keys.add('${option.variantUomId}');
      }
    }
    expect(
      keys.toSet().length,
      keys.length,
      reason: 'two catalogue rows share a unit id: $keys',
    );
  });
}
