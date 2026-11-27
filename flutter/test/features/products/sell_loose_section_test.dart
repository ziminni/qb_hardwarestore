// Sell loose on Add Product (sell-by-measure plan, Task 8): a bag counted in
// whole numbers can be set up for ½, ¼ and any number of kilos right when it
// is created, instead of hunting for "Add selling unit" in Edit afterwards.

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/features/products/widgets/products_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _units = [
  UnitOfMeasure(id: 1, code: 'KG', name: 'Kilogram'),
  UnitOfMeasure(id: 2, code: 'BAG', name: 'Bag', isWhole: true),
];

ProductFormResult? _result;

Future<void> _open(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  _result = null;
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              _result = await showDialog<ProductFormResult>(
                context: context,
                builder: (_) => const ProductsFormDialog(
                  categories: [Category(id: 1, name: 'Cement')],
                  brands: [Brand(id: 1, name: 'Holcim')],
                  units: _units,
                  products: [],
                  storageLocations: [StorageLocation(id: 4, name: 'Store')],
                ),
              );
            },
            child: const Text('Open form'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open form'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Product name'),
    'Portland Cement',
  );
  await tester.enterText(find.byKey(const ValueKey('sku-field')), 'CEM-40');
  await tester.pumpAndSettle();
}

Future<void> _tapKey(WidgetTester tester, Key key) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _enter(WidgetTester tester, Key key, String text) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.enterText(finder, text);
  await tester.pumpAndSettle();
}

/// By Quantity: BAG is the shop's only whole unit, so it becomes the base.
Future<void> _chooseBag(WidgetTester tester) async {
  await _tapKey(tester, const ValueKey('tracking-quantity'));
}

Future<void> _save(WidgetTester tester) async {
  final button = find.widgetWithText(FilledButton, 'Add product');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a quarter bag and kilos ride along with the new product', (
    tester,
  ) async {
    await _open(tester);
    await _chooseBag(tester);
    await _enter(tester, const ValueKey('base-price'), '260');

    expect(find.textContaining('Use Sell loose below'), findsOneWidget);

    await _tapKey(tester, const ValueKey('sell-loose-4'));
    await _enter(tester, const ValueKey('sell-loose-price-4'), '70');
    await _tapKey(tester, const ValueKey('sell-loose-measure'));
    await _enter(tester, const ValueKey('sell-loose-per-base'), '40');
    await _enter(tester, const ValueKey('sell-loose-measure-price'), '7.50');

    await _save(tester);

    final draft = _result!.draft!;
    expect(draft.baseUomId, 2);
    final quarter = draft.extraSellingUnits.singleWhere((u) => u.parts == 4);
    expect(quarter.sellingPrice, 70);
    final kilo = draft.extraSellingUnits.singleWhere(
      (u) => u.measurePerBase != null,
    );
    expect(kilo.uomId, 1);
    expect(kilo.measurePerBase, 40);
    expect(kilo.sellingPrice, 7.5);
    expect(draft.extraSellingUnits, hasLength(2));
  });

  testWidgets('nothing loose is added unless it is ticked', (tester) async {
    await _open(tester);
    await _chooseBag(tester);
    await _enter(tester, const ValueKey('base-price'), '260');
    await _save(tester);
    expect(_result!.draft!.extraSellingUnits, isEmpty);
  });

  testWidgets('an item counted in kilos has no Sell loose section', (
    tester,
  ) async {
    await _open(tester);
    expect(find.byKey(const ValueKey('sell-loose-4')), findsNothing);
  });
}
