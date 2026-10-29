// Phase 6 Task 4 (decision 11, F3): a till catalogue line carries the code of
// ITS OWN selling unit.
//
// The catalogue used to take `record.variant.barcode`, which is the variant's
// FIRST non-blank code (`product.dart:43`). A piece and a box of the same variant
// then answered to one code, so a scan could not tell them apart and the box
// factor was unreachable — the "one label, two things" landmine.

import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import '../../support/phase4_fakes.dart';
import 'package:flutter_test/flutter_test.dart';

/// A variant sold by the piece AND by the box, each with its own server code.
VariantUom pcUnit() => const VariantUom(
  id: 120,
  variantId: 12,
  uomId: 1,
  uomCode: 'PC',
  uomName: 'Piece',
  barcodeQr: 'QB000012-3',
  conversionFactor: 1,
  defaultSellingPrice: 20,
);

VariantUom boxUnit() => const VariantUom(
  id: 130,
  variantId: 12,
  uomId: 2,
  uomCode: 'BOX',
  uomName: 'Box of 100',
  barcodeQr: 'QB000013-0',
  conversionFactor: 100,
  defaultSellingPrice: 1900,
);

void main() {
  late InventoryViewmodel inventory;
  late PosTransactionViewmodel cart;

  setUp(() {
    inventory = InventoryViewmodel.seeded(
      products: [
        product(
          id: 12,
          name: 'Copper Wire',
          variants: [
            variant(
              id: 12,
              productId: 12,
              name: 'THHN 3.5mm',
              baseUomCode: 'PC',
              sellingUoms: [pcUnit(), boxUnit()],
            ),
          ],
        ),
      ],
      batches: [batch(id: 1, variantId: 12, qty: 500, cost: 10)],
    );
    // The box's factor is 100 on its OWN selling unit (decision 01/06): the till
    // catalogue reads it there, so "the box's factor" is a number this test can
    // tell apart from the piece's without any local tracking config.
    cart = PosTransactionViewmodel(inventory);
  });

  test('a scan of the BOX code resolves the box unit, not the piece', () {
    final hit = cart.findByBarcode('qb000013-0');

    expect(
      hit,
      isNotNull,
      reason:
          'QB000013-0 is the box selling unit. The catalogue must carry each '
          'unit\'s own code (decision 11 F3), otherwise only the first code on '
          'the variant is ever scannable.',
    );
    expect(hit!.variantUomId, boxUnit().id);
    expect(hit.unit, 'BOX');
    expect(
      hit.conversionFactor,
      100,
      reason: 'the box is 100 pieces: a scan must add the box, not one piece',
    );
  });

  test('a scan of the PIECE code still resolves the piece unit', () {
    final hit = cart.findByBarcode(' QB000012-3 ');

    expect(hit, isNotNull);
    expect(hit!.variantUomId, pcUnit().id);
    expect(hit.unit, 'PC');
    expect(hit.conversionFactor, 1);
  });

  test('every catalogue line carries its own unit code', () {
    final options = cart.saleOptionsFor(
      cart.filteredProducts.firstWhere((item) => item.variantId == 12),
    );

    expect(options.map((option) => option.barcode), [
      'QB000012-3',
      'QB000013-0',
    ]);
  });

  test('an unknown code resolves nothing', () {
    expect(cart.findByBarcode('QB999999-9'), isNull);
  });
}
