// Sell by measure: a bag also sold by the kilo can be counted in kilos ("390
// kg left" on an opened pallet), and the adjustment travels in KG with its
// unit so the server converts it (design: 2026-11-27-sell-by-measure-design).

import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/stock_on_hand.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_adjust_stock_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

class _CapturingInventoryRepository extends FakeInventoryRepository {
  _CapturingInventoryRepository() : super();

  final recorded = <({double quantity, int? variantUomId})>[];

  @override
  Future<StockAdjustment> recordAdjustment({
    required int variantId,
    required StockAdjustmentType type,
    required double quantity,
    String remarks = '',
    int? locationId,
    int? variantUomId,
  }) async {
    recorded.add((quantity: quantity, variantUomId: variantUomId));
    return StockAdjustment(
      id: 99,
      variantId: variantId,
      userId: 1,
      adjustmentType: type,
      quantityAdjusted: quantity,
      remarks: remarks,
      timestamp: DateTime(2026, 11, 27),
    );
  }
}

final _cement = product(
  id: 8,
  name: 'Portland Cement',
  variants: [
    variant(
      id: 8,
      productId: 8,
      name: '40kg',
      baseUomId: 3,
      baseUomCode: 'BAG',
      sellingUoms: [
        variantUom(id: 30, variantId: 8, uomId: 3, uomCode: 'BAG', price: 260),
        variantUom(
          id: 31,
          variantId: 8,
          uomId: 5,
          uomCode: 'KG',
          factor: 0.025,
          price: 7.5,
          measurePerBase: 40,
        ),
      ],
    ),
  ],
);

const _stock = [
  StockOnHand(
    variantId: 8,
    locationId: 1,
    locationName: 'Store',
    locationActive: true,
    isHome: true,
    qty: 9.75,
  ),
];

void main() {
  testWidgets('counting in KG starts at the kilos on hand and returns KG', (
    tester,
  ) async {
    InventoryAdjustStockResult? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<InventoryAdjustStockResult>(
                  context: context,
                  builder: (_) => InventoryAdjustStockDialog(
                    product: _cement,
                    variant: _cement.variants.first,
                    currentStock: 9.75,
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('adjust-unit-31')));
    await tester.pumpAndSettle();
    final field = tester.widget<TextFormField>(find.byType(TextFormField).first);
    expect(field.controller!.text, '390');

    await tester.enterText(find.byType(TextFormField).first, '389.5');
    await tester.pumpAndSettle();
    expect(find.text('Decrease by 0.5'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Confirm Adjustment'));
    await tester.pumpAndSettle();

    expect(result!.quantity, 389.5);
    expect(result!.variantUomId, 31);
  });

  test('a KG count sends the kilo difference with its unit', () async {
    final repository = _CapturingInventoryRepository();
    final store = InventoryViewmodel(
      products: FakeProductsRepository(products: [_cement], stockOnHand: _stock),
      inventory: repository,
      catalogue: FakeCatalogueRepository(),
    );
    await store.load();

    final ok = await store.adjustStock(
      variantId: 8,
      newQuantity: 389.5,
      reason: 'Damaged Items',
      notes: 'Spilled while scooping',
      variantUomId: 31,
    );

    expect(ok, isTrue);
    expect(repository.recorded.single.quantity, -0.5);
    expect(repository.recorded.single.variantUomId, 31);
  });
}
