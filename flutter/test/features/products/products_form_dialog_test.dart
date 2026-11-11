// Task 7 (phase 1d): "Add product" asks how the product is sold, and the two
// invented screens it used to feed are gone.
//
// What this locks, step by step:
//   1. Basic information keeps the fields Phase 4 Task 4 left it with;
//   2. "How is this product sold?" carries the base unit and price plus repeatable
//      extra-unit rows (Bag = 40 kg at ₱270), each with a live helper, and mirrors
//      the SERVER's rules (factor not 1, at least 0.01, at most 2 decimals, no
//      duplicate unit, price not negative) so a refused row is caught before the
//      POST chain starts;
//   3. "Stock levels" keeps the thresholds and the storage location, and says the
//      location is saved on this device only (decision 15: the server has no
//      location field);
//   - an edit keeps the base unit FROZEN: the server refuses to change it;
//   - HCI acceptance: Tab runs the steps then the footer, Esc closes, and nothing
//     clips at 1.3x text in a 760 px window with the real fonts.

import 'dart:io';

import 'package:client/core/format/format.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/products/widgets/products_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/phase4_fakes.dart';

const _categories = [Category(id: 1, name: 'Cement')];
const _brands = [Brand(id: 1, name: 'Holcim')];

/// The base unit is a measured one (kg) so the helper's arithmetic is the
/// example the plan writes down: 1 Bag = 40 kg at ₱270 is ₱6.75 per kg.
const _units = [
  UnitOfMeasure(id: 1, code: 'KG', name: 'Kilogram'),
  UnitOfMeasure(id: 2, code: 'BAG', name: 'Bag', isWhole: true),
  UnitOfMeasure(id: 3, code: 'BOX', name: 'Box', isWhole: true),
];

/// The last dialog result. Set when the dialog pops, read after the test taps a
/// footer button.
ProductFormResult? lastResult;

Future<void> _loadAppFonts() async {
  for (final (family, files) in [
    ('OpenSans', ['OpenSans-Regular.ttf', 'OpenSans-Bold.ttf']),
    ('Cinzel', ['Cinzel-Regular.ttf', 'Cinzel-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }
}

/// Opens the dialog the way the Products page does.
Future<void> openForm(
  WidgetTester tester, {
  Product? product,
  String locationHint = '',
  Size size = const Size(1440, 1000),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  lastResult = null;

  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                lastResult = await showDialog<ProductFormResult>(
                  context: context,
                  builder: (_) => ProductsFormDialog(
                    categories: _categories,
                    brands: _brands,
                    units: _units,
                    products: const [],
                    product: product,
                    locationHint: locationHint,
                  ),
                );
              },
              child: const Text('Open form'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open form'));
  await tester.pumpAndSettle();
}

/// Scrolls [key] into the dialog's viewport and taps it. The form is taller than
/// the window, so anything below the fold has to be reached first.
Future<void> tapKey(WidgetTester tester, Key key) async {
  // A focused text field keeps asking to be shown on screen, which undoes the
  // scroll `ensureVisible` just did. Drop focus first, then scroll.
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Picks [item] out of the dropdown under [field].
Future<void> pick(WidgetTester tester, Key field, String item) async {
  await tapKey(tester, field);
  await tester.tap(find.text(item).last);
  await tester.pumpAndSettle();
}

/// Adds one extra selling unit row and fills it in.
Future<void> addBagRow(
  WidgetTester tester, {
  String factor = '40',
  String price = '270',
}) async {
  await tapKey(tester, const ValueKey('add-unit-row'));
  await pick(tester, const ValueKey('row-unit-0'), 'Bag (BAG)');
  await tester.enterText(find.byKey(const ValueKey('row-factor-0')), factor);
  await tester.enterText(find.byKey(const ValueKey('row-price-0')), price);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester, {String label = 'Add product'}) async {
  final button = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Product portlandCement() => product(
  id: 7,
  name: 'Portland Cement',
  categoryName: 'Cement',
  brandName: 'Holcim',
  variants: [
    variant(
      id: 7,
      productId: 7,
      name: '40 kg bag',
      baseUomCode: 'BAG',
      sellingUoms: const [
        VariantUom(
          id: 70,
          variantId: 7,
          uomId: 2,
          uomCode: 'BAG',
          uomName: 'Bag',
          barcodeQr: 'QB000007-1',
          conversionFactor: 1,
          defaultSellingPrice: 270,
        ),
      ],
    ),
  ],
);

/// A multi-unit product the way the server lists it once packaging exists: the
/// BAG (factor 40) comes back BEFORE the KG base unit (factor 1), so list order
/// says nothing about which row is the base unit.
Product multiUnitCement() => product(
  id: 8,
  name: 'Portland Cement',
  variants: [
    variant(
      id: 8,
      productId: 8,
      name: 'Standard',
      baseUomCode: 'KG',
      sellingUoms: const [
        VariantUom(
          id: 81,
          variantId: 8,
          uomId: 2,
          uomCode: 'BAG',
          uomName: 'Bag',
          barcodeQr: 'QB000081-6',
          conversionFactor: 40,
          defaultSellingPrice: 270,
        ),
        VariantUom(
          id: 80,
          variantId: 8,
          uomId: 1,
          uomCode: 'KG',
          uomName: 'Kilogram',
          barcodeQr: 'QB000080-5',
          conversionFactor: 1,
          defaultSellingPrice: 6.75,
        ),
      ],
    ),
  ],
);

/// The same product with the base row missing from the server's answer, which
/// is the one case the form must refuse rather than price another unit.
Product multiUnitCementWithoutBaseRow() => product(
  id: 9,
  name: 'Portland Cement',
  variants: [
    variant(
      id: 9,
      productId: 9,
      name: 'Standard',
      baseUomCode: 'KG',
      sellingUoms: const [
        VariantUom(
          id: 91,
          variantId: 9,
          uomId: 2,
          uomCode: 'BAG',
          uomName: 'Bag',
          barcodeQr: 'QB000091-2',
          conversionFactor: 40,
          defaultSellingPrice: 270,
        ),
      ],
    ),
  ],
);

void main() {
  setUpAll(_loadAppFonts);

  group('the three steps', () {
    testWidgets('are numbered and titled in order', (tester) async {
      await openForm(tester);

      expect(find.text('Basic information'), findsOneWidget);
      expect(find.text('How is this product sold?'), findsOneWidget);
      expect(find.text('Stock levels'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });
  });

  group('step 2: how is this product sold?', () {
    testWidgets('an extra unit row shows the live helper in words', (
      tester,
    ) async {
      await openForm(tester);
      await addBagRow(tester);

      // The plan's own example. Money through formatPeso, quantity through
      // formatQuantity, and a middle dot rather than an em dash.
      expect(
        find.text('1 BAG = 40 KG · ${formatPeso(270 / 40)} per KG'),
        findsOneWidget,
      );
    });

    testWidgets('a row can be removed again', (tester) async {
      await openForm(tester);
      await addBagRow(tester);
      expect(find.text('Bag (BAG)'), findsWidgets);

      await tapKey(tester, const ValueKey('remove-row-0'));

      expect(find.byKey(const ValueKey('row-factor-0')), findsNothing);
      expect(find.byKey(const ValueKey('add-unit-row')), findsOneWidget);
    });

    testWidgets('a factor of exactly 1 is refused: that is the base unit', (
      tester,
    ) async {
      await openForm(tester);
      await addBagRow(tester, factor: '1');
      await save(tester);

      expect(find.textContaining('base unit'), findsWidgets);
      expect(lastResult, isNull, reason: 'a refused row must not pop the form');
    });

    testWidgets('a factor under 0.01 is refused', (tester) async {
      await openForm(tester);
      await addBagRow(tester, factor: '0.001');
      await save(tester);

      expect(find.textContaining('at least 0.01'), findsOneWidget);
      expect(lastResult, isNull);
    });

    testWidgets('a factor with three decimals is refused', (tester) async {
      await openForm(tester);
      await addBagRow(tester, factor: '1.005');
      await save(tester);

      expect(find.textContaining('at most 2 decimals'), findsOneWidget);
      expect(lastResult, isNull);
    });

    testWidgets('the same unit twice is refused, including the base unit', (
      tester,
    ) async {
      await openForm(tester);
      // KG is the base unit; the server would answer INVALID_SELLING_UNIT.
      await tapKey(tester, const ValueKey('add-unit-row'));
      await pick(tester, const ValueKey('row-unit-0'), 'Kilogram (KG)');
      await tester.enterText(find.byKey(const ValueKey('row-factor-0')), '40');
      await tester.enterText(find.byKey(const ValueKey('row-price-0')), '270');
      await save(tester);

      expect(find.textContaining('already used'), findsOneWidget);
      expect(lastResult, isNull);
    });

    testWidgets('a negative price is refused', (tester) async {
      await openForm(tester);
      await addBagRow(tester, price: '-5');
      await save(tester);

      expect(find.textContaining('cannot be negative'), findsOneWidget);
      expect(lastResult, isNull);
    });

    testWidgets('the base unit and every extra unit reach the draft', (
      tester,
    ) async {
      await openForm(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Product name'),
        'Portland Cement',
      );
      await addBagRow(tester);
      await save(tester);

      final draft = lastResult!.draft!;
      expect(draft.baseUomId, 1, reason: 'kg is the base unit');
      expect(draft.extraSellingUnits, hasLength(1));
      final bag = draft.extraSellingUnits.single;
      expect(bag.uomId, 2);
      expect(bag.uomCode, 'BAG', reason: 'the partial-failure copy names it');
      expect(bag.conversionFactor, 40);
      expect(bag.sellingPrice, 270);
    });
  });

  group('step 3: stock levels', () {
    testWidgets('the info banner says how stock really arrives', (
      tester,
    ) async {
      await openForm(tester);

      expect(
        find.text('Stock arrives through a purchase order, then Receiving.'),
        findsOneWidget,
      );
    });

    testWidgets('the storage location says it stays on this device', (
      tester,
    ) async {
      await openForm(tester);

      expect(find.text('Saved on this device only'), findsOneWidget);
    });

    testWidgets('a typed location travels in the draft', (tester) async {
      await openForm(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Product name'),
        'Portland Cement',
      );
      await tester.enterText(
        find.byKey(const ValueKey('location-field')),
        'Rack A-01',
      );
      await save(tester);

      expect(lastResult!.draft!.locationHint, 'Rack A-01');
    });
  });

  group('editing an existing product', () {
    testWidgets('keeps the base unit frozen, and says why', (tester) async {
      await openForm(tester, product: portlandCement());

      expect(find.text('Bag (BAG)'), findsOneWidget);
      expect(
        find.textContaining('keeps this unit for its whole history'),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('base-unit-picker')),
        findsNothing,
        reason: 'the server refuses a base-unit change (INVALID_VARIANT)',
      );
    });

    testWidgets('carries the location the device already knows', (
      tester,
    ) async {
      await openForm(
        tester,
        product: portlandCement(),
        locationHint: 'Rack A-01',
      );

      final field = tester.widget<TextFormField>(
        find.byKey(const ValueKey('location-field')),
      );
      expect(field.controller?.text, 'Rack A-01');
    });

    testWidgets('has no extra-unit rows: those are added after creation', (
      tester,
    ) async {
      await openForm(tester, product: portlandCement());

      expect(find.byKey(const ValueKey('add-unit-row')), findsNothing);
    });

    // Regression: the base unit is the variant's `base_uom` at factor 1, not
    // whatever row the server happens to list first. Reading `firstOrNull`
    // priced the form "per KG" with the BAG's ₱270 and PATCHed the BAG row.
    testWidgets('prices and saves the BASE unit when a bag is listed first', (
      tester,
    ) async {
      await openForm(tester, product: multiUnitCement());

      expect(find.text('Price per KG'), findsOneWidget);
      final price = tester.widget<TextFormField>(
        find.byKey(const ValueKey('base-price')),
      );
      final shown = price.controller?.text;

      await save(tester, label: 'Save changes');

      final draft = lastResult!.edit!;
      expect(
        draft.sellingUnitId,
        80,
        reason: 'the KG selling unit, never the BAG row listed first',
      );
      expect(draft.sellingPrice, 6.75);
      expect(
        shown,
        formatQuantity(6.75),
        reason: 'the KG row\'s price, not the BAG row\'s 270',
      );
    });

    testWidgets('refuses to save when the base selling unit is missing', (
      tester,
    ) async {
      await openForm(tester, product: multiUnitCementWithoutBaseRow());
      await save(tester, label: 'Save changes');

      expect(find.textContaining('no base selling unit'), findsOneWidget);
      expect(
        lastResult,
        isNull,
        reason: 'never PATCH a price onto some other unit instead',
      );
    });
  });

  group('HCI acceptance', () {
    /// The name of whatever currently has keyboard focus.
    String focusedName() {
      final context = FocusManager.instance.primaryFocus?.context;
      if (context == null) return 'nothing';
      final field = context.findAncestorWidgetOfExactType<TextField>();
      if (field != null) return 'field:${field.decoration?.labelText}';
      final dropdown = context
          .findAncestorWidgetOfExactType<DropdownButtonFormField<int>>();
      if (dropdown != null) return 'field:${dropdown.decoration.labelText}';
      final text = context.findAncestorWidgetOfExactType<TextButton>();
      if (text != null) return 'button:${(text.child! as Text).data}';
      final filled = context.findAncestorWidgetOfExactType<FilledButton>();
      if (filled != null) return 'button:${(filled.child! as Text).data}';
      if (context.findAncestorWidgetOfExactType<IconButton>() != null) {
        return 'header-close';
      }
      return 'other';
    }

    testWidgets('Tab runs the steps and then the footer actions', (
      tester,
    ) async {
      // A window tall enough to show the whole form: this test is about the
      // ORDER of the stops, and the 1.3x tests below cover what happens when the
      // form has to scroll.
      await openForm(tester, size: const Size(1440, 2000));
      await addBagRow(tester);

      // Start the walk at the top of the dialog rather than wherever the last
      // tapped form field left the focus.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      final stops = <String>[];
      for (var i = 0; i < 24; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        final name = focusedName();
        if (name == 'button:Add product') {
          stops.add(name);
          break;
        }
        stops.add(name);
      }

      void expectBefore(String first, String second) {
        expect(stops, contains(first));
        expect(stops, contains(second));
        expect(
          stops.indexOf(first),
          lessThan(stops.indexOf(second)),
          reason: '"$first" must come before "$second"',
        );
      }

      expectBefore('field:Product name', 'field:Base unit');
      expectBefore('field:Base unit', 'field:Price per KG');
      expectBefore('field:Price per KG', 'field:Selling unit');
      expectBefore('field:Selling unit', 'field:Storage location');
      expectBefore('field:Storage location', 'button:Cancel');
      expectBefore('button:Cancel', 'button:Add product');
    });

    testWidgets('Esc closes the form without saving', (tester) async {
      await openForm(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(ProductsFormDialog), findsNothing);
      expect(lastResult, isNull);
    });

    for (final size in const [Size(1440, 900), Size(760, 900)]) {
      testWidgets(
        'nothing overflows at 1.3x text in a ${size.width.toInt()} px window',
        (tester) async {
          await openForm(tester, size: size, textScale: 1.3);
          await addBagRow(tester);

          expect(tester.takeException(), isNull);

          // Scrolling to the last field is where a form that only fits at 1.0x
          // gives itself away.
          await tester.ensureVisible(
            find.byKey(const ValueKey('location-field')),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Add product').last);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('How is this product sold?'), findsOneWidget);
        },
      );
    }
  });
}
