// Sell by measure: a kilo card of a 40 kg bag, or a metre card of a 150 m
// roll. The till reads what is left by MULTIPLYING the bags by the kilos per
// bag; dividing by the rounded factor (0.006667 for a metre) would show a
// 150 m roll as 149.99 m.

import 'package:client/data/models/pos_transaction.dart';
import 'package:client/features/pos/widgets/pos_product_browser.dart';
import 'package:client/features/pos/widgets/pos_sale_quantity_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

PosCatalogItem _item({
  required String unit,
  required double factor,
  required double baseStock,
  double? measurePerBase,
}) => PosCatalogItem(
  variantUomId: 1,
  variantId: 1,
  productName: 'THHN Wire',
  variantName: '2.0mm',
  unit: unit,
  barcode: '',
  conversionFactor: factor,
  unitPrice: 12,
  availableBaseStock: baseStock,
  measurePerBase: measurePerBase,
);

void main() {
  test('a metre card reads the exact metres left on the rolls', () {
    final metre = _item(
      unit: 'M',
      factor: 0.006667,
      baseStock: 1,
      measurePerBase: 150,
    );
    expect(metre.availableSaleQuantity, 150);
    expect(metre.isMeasured, isTrue);
  });

  test('a kilo card reads 9.75 bags as 390 kg', () {
    final kilo = _item(
      unit: 'KG',
      factor: 0.025,
      baseStock: 9.75,
      measurePerBase: 40,
    );
    expect(kilo.availableSaleQuantity, 390);
  });

  test('an ordinary unit still divides by its factor', () {
    final box = _item(unit: 'BOX', factor: 12, baseStock: 36);
    expect(box.availableSaleQuantity, 3);
    expect(box.isMeasured, isFalse);
  });

  group('the bag card of a variant also sold by the kilo', () {
    final bag = _item(unit: 'BAG', factor: 1, baseStock: 2.8125);
    final kilo = _item(
      unit: 'KG',
      factor: 0.025,
      baseStock: 2.8125,
      measurePerBase: 40,
    );

    test('reads 2.8125 bags as 2 BAG + 32.5 KG', () {
      expect(posMeasuredStockLabel(bag, [bag, kilo]), '2 BAG + 32.5 KG');
    });

    test('is null without a measured unit, or on the kilo card itself', () {
      expect(posMeasuredStockLabel(bag, [bag]), isNull);
      expect(posMeasuredStockLabel(kilo, [bag, kilo]), isNull);
    });

    testWidgets('the till card shows it instead of 2.813 bag', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosProductBrowser(
              products: [bag],
              onSearch: (_) {},
              onSelect: (_) {},
              searchController: TextEditingController(),
              searchFocusNode: FocusNode(),
              onSubmitted: (_) {},
              stockLabelFor: (item) => posMeasuredStockLabel(item, [bag, kilo]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 BAG + 32.5 KG in stock'), findsOneWidget);
      expect(find.textContaining('2.813'), findsNothing);
    });
  });

  group('the quantity dialog for a kilo card', () {
    final kilo = _item(
      unit: 'KG',
      factor: 0.025,
      baseStock: 9.75,
      measurePerBase: 40,
    );

    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PosSaleQuantityDialog(product: kilo, options: [kilo]),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    String typed(WidgetTester tester) => tester
        .widget<TextFormField>(find.byType(TextFormField))
        .controller!
        .text;

    testWidgets('accepts 7.5 kg', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextFormField), '7.5');
      await tester.pumpAndSettle();
      expect(typed(tester), '7.5');
      expect(find.text('Enter a valid quantity'), findsNothing);
    });

    testWidgets('refuses a third decimal (7.555 kg)', (tester) async {
      await pump(tester);
      await tester.enterText(find.byType(TextFormField), '7.55');
      await tester.enterText(find.byType(TextFormField), '7.555');
      await tester.pumpAndSettle();
      expect(typed(tester), '7.55');
    });
  });
}
