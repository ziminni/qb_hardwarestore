// Owner 2026-11-18: the teammate's "How is this product tracked?" chips and the
// "Allow fractional quantity?" switch, on our real units.
//
// Pinned here: a chip picks the first unit of its kind; picking a unit in the
// dropdown lights the matching chip; the switch flips to a unit of the same kind
// with the other whole/fraction rule, and is locked (saying why) when the shop
// has no such unit; editing shows both locked.

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/features/products/widgets/products_form_dialog.dart';
import 'package:client/features/products/widgets/tracking_kind.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _units = [
  UnitOfMeasure(id: 1, code: 'PC', name: 'Piece', isWhole: true),
  UnitOfMeasure(id: 2, code: 'KG', name: 'Kilogram'),
  UnitOfMeasure(id: 3, code: 'M', name: 'Metre'),
  UnitOfMeasure(id: 4, code: 'CU.M', name: 'Cubic metre'),
  UnitOfMeasure(id: 5, code: 'BAG', name: 'Bag', isWhole: true),
];

Future<void> _open(
  WidgetTester tester, {
  List<UnitOfMeasure> units = _units,
}) async {
  tester.view.physicalSize = const Size(1200, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: ProductsFormDialog(
          categories: const [Category(id: 1, name: 'Aggregates')],
          brands: const [Brand(id: 1, name: 'Local')],
          units: units,
          products: const [],
          storageLocations: const [StorageLocation(id: 1, name: 'Store')],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _selected(WidgetTester tester, TrackingKind kind) => tester
    .widget<ChoiceChip>(find.byKey(ValueKey('tracking-${kind.name}')))
    .selected;

SwitchListTile _switch(WidgetTester tester) => tester.widget<SwitchListTile>(
  find.byKey(const ValueKey('fraction-switch')),
);

void main() {
  test('units are sorted into kinds by their code', () {
    expect(TrackingKind.of(_units[0]), TrackingKind.quantity);
    expect(TrackingKind.of(_units[1]), TrackingKind.weight);
    expect(TrackingKind.of(_units[2]), TrackingKind.length);
    expect(TrackingKind.of(_units[3]), TrackingKind.volume);
    expect(TrackingKind.of(_units[4]), TrackingKind.quantity);
  });

  testWidgets('a chip picks the first unit of its kind', (tester) async {
    await _open(tester);
    expect(_selected(tester, TrackingKind.quantity), isTrue);
    expect(find.text('Selling price per PC'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('tracking-volume')));
    await tester.pumpAndSettle();
    expect(_selected(tester, TrackingKind.volume), isTrue);
    expect(find.text('Selling price per CU.M'), findsOneWidget);
    expect(find.text('Sold by litre or cubic metre'), findsOneWidget);
  });

  testWidgets('the unit list offers only units of the chosen kind', (
    tester,
  ) async {
    await _open(tester);
    await tester.tap(find.byKey(const ValueKey('base-unit-picker')));
    await tester.pumpAndSettle();
    expect(find.text('Bag (BAG)'), findsWidgets);
    expect(find.text('Metre (M)'), findsNothing);
  });

  testWidgets('the switch shows the unit rule and is locked without a twin', (
    tester,
  ) async {
    await _open(tester);
    // PC is whole and the shop has no fractional counted unit: locked, off.
    expect(_switch(tester).value, isFalse);
    expect(_switch(tester).onChanged, isNull);
    expect(
      find.textContaining('PC is always sold in whole numbers'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('tracking-weight')));
    await tester.pumpAndSettle();
    // KG allows parts, and no whole weight unit exists: on, locked.
    expect(_switch(tester).value, isTrue);
    expect(_switch(tester).onChanged, isNull);
  });

  testWidgets('the switch flips to a twin unit of the same kind', (
    tester,
  ) async {
    await _open(
      tester,
      units: const [
        UnitOfMeasure(id: 1, code: 'PC', name: 'Piece', isWhole: true),
        UnitOfMeasure(id: 7, code: 'LOT', name: 'Loose lot'),
      ],
    );
    expect(_switch(tester).value, isFalse);
    await tester.tap(find.byKey(const ValueKey('fraction-switch')));
    await tester.pumpAndSettle();
    expect(_switch(tester).value, isTrue);
    expect(find.text('Selling price per LOT'), findsOneWidget);
  });

  testWidgets('a kind the shop has no unit for cannot be chosen', (
    tester,
  ) async {
    await _open(
      tester,
      units: const [
        UnitOfMeasure(id: 1, code: 'PC', name: 'Piece', isWhole: true),
      ],
    );
    final chip = tester.widget<ChoiceChip>(
      find.byKey(const ValueKey('tracking-length')),
    );
    expect(chip.onSelected, isNull);
  });
}
