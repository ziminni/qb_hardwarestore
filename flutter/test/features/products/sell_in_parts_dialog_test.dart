// Sell in parts (planning/sell-in-parts): an opened bag sold as ½ or ¼, priced
// on its own, from the "Add selling unit" dialog.

import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/product_writes.dart';
import 'package:client/features/products/widgets/selling_unit_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

void main() {
  final cement = variant(
    id: 1,
    productId: 1,
    name: '40kg',
    baseUomId: 3,
    baseUomCode: 'BAG',
    sellingUoms: [
      variantUom(
        id: 11,
        variantId: 1,
        uomId: 3,
        uomCode: 'BAG',
        uomName: 'Bag',
        price: 260,
        isWhole: true,
      ),
    ],
  );

  Future<List<NewSellingUnit>> open(
    WidgetTester tester, {
    required ProductVariant variantUnderTest,
  }) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final submitted = <NewSellingUnit>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AddSellingUnitDialog(
            productName: 'Portland Cement',
            variant: variantUnderTest,
            units: const [
              UnitOfMeasure(id: 3, code: 'BAG', name: 'Bag', isWhole: true),
            ],
            onSubmit: (unit) async {
              submitted.add(unit);
              return null;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return submitted;
  }

  testWidgets('a quarter bag is posted as parts with its own price', (
    tester,
  ) async {
    final submitted = await open(tester, variantUnderTest: cement);
    await tester.tap(find.text('Sell in parts'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('part-4')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('part-price')), '70');
    await tester.pumpAndSettle();

    expect(find.textContaining('Proportional price: ₱65.00'), findsOneWidget);
    expect(find.textContaining('₱20.00 more per BAG'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('add-unit-save')));
    await tester.pumpAndSettle();

    final unit = submitted.single;
    expect(unit.parts, 4);
    expect(unit.sellingPrice, 70);
    expect(unit.partUnitBody(), containsPair('parts', 4));
    expect(unit.partUnitBody(), containsPair('default_selling_price', 70.0));
  });

  testWidgets('a part the item already sells is not offered again', (
    tester,
  ) async {
    final withQuarter = variant(
      id: 1,
      productId: 1,
      baseUomId: 3,
      baseUomCode: 'BAG',
      sellingUoms: [
        variantUom(id: 11, variantId: 1, uomId: 3, uomCode: 'BAG', price: 260),
        variantUom(
          id: 12,
          variantId: 1,
          uomId: 9,
          uomCode: 'QTR',
          factor: 0.25,
          price: 70,
        ),
      ],
    );
    await open(tester, variantUnderTest: withQuarter);
    await tester.tap(find.text('Sell in parts'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('part-4')), findsNothing);
    expect(find.byKey(const ValueKey('part-2')), findsOneWidget);
  });

  testWidgets('an item measured in kilos is not offered parts', (
    tester,
  ) async {
    final loose = variant(
      id: 2,
      productId: 1,
      baseUomId: 2,
      baseUomCode: 'KG',
      baseUomIsWhole: false,
    );
    await open(tester, variantUnderTest: loose);
    await tester.tap(find.text('Sell in parts'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('parts-measured-note')), findsOneWidget);
    final save = tester.widget<FilledButton>(
      find.byKey(const ValueKey('add-unit-save')),
    );
    expect(save.onPressed, isNull);
  });
}
