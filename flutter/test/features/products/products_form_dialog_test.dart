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
import 'package:client/data/models/storage_location.dart';
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

/// Phase 5 F4: every product form now needs the server's pick-up points. Store
/// is the default a new product gets.
const _locations = [
  StorageLocation(id: 4, name: 'Store'),
  StorageLocation(id: 9, name: 'Bodega'),
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
                    // A B4 product always carries its pick-up point; these
                    // fixtures predate the field, so give an edit a real one.
                    product: product?.storedAtId == null
                        ? product?.copyWith(
                            storedAtId: 4,
                            storedAtName: 'Store',
                          )
                        : product,
                    locationHint: locationHint,
                    storageLocations: _locations,
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

/// Fills what step 1 requires on a NEW product (owner 2026-11-18: SKU is
/// required, as in the teammate form).
Future<void> fillBasics(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Product name'),
    'Portland Cement',
  );
  await tester.enterText(find.byKey(const ValueKey('sku-field')), 'CEM-40');
  await tester.pumpAndSettle();
}

/// By Weight (KG) sold in bags of [size] kg.
Future<void> choosePackagedBag(
  WidgetTester tester, {
  String size = '40',
}) async {
  await tapKey(tester, const ValueKey('tracking-weight'));
  final packaged = find.text('Packaged');
  await tester.ensureVisible(packaged);
  await tester.pumpAndSettle();
  await tester.tap(packaged);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('package-size')), size);
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester, {String label = 'Add product'}) async {
  final button = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

/// The cement the shop never discounts (owner ruling).
Product cementNeverDiscounted() => product(
  id: 8,
  name: 'Portland Cement',
  categoryName: 'Cement',
  brandName: 'Holcim',
  allowDiscount: false,
  variants: [
    variant(
      id: 8,
      productId: 8,
      name: '40 kg bag',
      baseUomId: 2,
      baseUomCode: 'BAG',
      sellingUoms: const [
        VariantUom(
          id: 80,
          variantId: 8,
          uomId: 2,
          uomCode: 'BAG',
          uomName: 'Bag',
          barcodeQr: '',
          conversionFactor: 1,
          defaultSellingPrice: 270,
          uomIsWhole: true,
        ),
      ],
    ),
  ],
);

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

  group('the teammate form (owner 2026-11-18)', () {
    testWidgets('a new product has the three numbered steps in order', (
      tester,
    ) async {
      await openForm(tester);
      expect(find.text('Basic Information'), findsOneWidget);
      expect(find.text('Inventory Tracking'), findsOneWidget);
      expect(find.text('Pricing & Initial Stock'), findsOneWidget);
      expect(find.text('First variant'), findsOneWidget);
      expect(find.byKey(const ValueKey('stock-preview')), findsOneWidget);
    });

    testWidgets('the SKU is required on a new product', (tester) async {
      await openForm(tester);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Product name'),
        'Portland Cement',
      );
      await save(tester);
      expect(find.text('Enter an SKU.'), findsOneWidget);
      expect(lastResult, isNull);
    });

    testWidgets('a blank barcode is allowed: the server generates one', (
      tester,
    ) async {
      await openForm(tester);
      await fillBasics(tester);
      await save(tester);
      expect(lastResult!.draft!.barcodeQr, '');
      expect(lastResult!.draft!.sku, 'CEM-40');
    });

    testWidgets('initial stock and cost save directly in the base unit without hidden extra selling units', (
      tester,
    ) async {
      await openForm(tester);
      await fillBasics(tester);
      await tapKey(tester, const ValueKey('tracking-weight'));
      expect(find.byKey(const ValueKey('stock-form')), findsNothing);
      await tester.enterText(find.byKey(const ValueKey('cost-field')), '5.50');
      await tester.enterText(find.byKey(const ValueKey('base-price')), '6.75');
      await tester.enterText(find.byKey(const ValueKey('initial-field')), '20');
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Total available: ${formatQuantity(20)} KG'),
        findsOneWidget,
      );
      await save(tester);

      final draft = lastResult!.draft!;
      expect(draft.baseUomId, 1, reason: 'KG');
      expect(draft.sellingPrice, 6.75);
      expect(draft.extraSellingUnits, isEmpty);
      expect(draft.openingQty, 20);
      expect(draft.openingUnitCost, 5.5);
    });

    testWidgets('no initial stock means no opening stock', (tester) async {
      await openForm(tester);
      await fillBasics(tester);
      await save(tester);
      expect(lastResult!.draft!.openingQty, 0);
      expect(lastResult!.draft!.extraSellingUnits, isEmpty);
    });

    testWidgets('a negative price is refused', (tester) async {
      await openForm(tester);
      await fillBasics(tester);
      await tester.enterText(find.byKey(const ValueKey('base-price')), '-1');
      await save(tester);
      expect(find.text('The price cannot be negative.'), findsOneWidget);
      expect(lastResult, isNull);
    });

    testWidgets('the shelf note on this device is kept, not shown', (
      tester,
    ) async {
      await openForm(tester, locationHint: 'Rack A-01');
      await fillBasics(tester);
      await save(tester);
      expect(find.byKey(const ValueKey('location-field')), findsNothing);
      expect(lastResult!.draft!.locationHint, 'Rack A-01');
    });
  });

  group('editing an existing product', () {
    testWidgets('shows basics and pricing, never the unit or stock', (
      tester,
    ) async {
      await openForm(tester, product: portlandCement());

      expect(find.text('Pricing & Stock Levels'), findsOneWidget);
      expect(find.byKey(const ValueKey('base-unit-picker')), findsNothing);
      expect(find.byKey(const ValueKey('initial-field')), findsNothing);
      expect(find.byKey(const ValueKey('cost-field')), findsNothing);
      expect(find.byKey(const ValueKey('stored-at-picker')), findsOneWidget);
    });

    testWidgets('keeps the shelf note the device already knows', (
      tester,
    ) async {
      await openForm(
        tester,
        product: multiUnitCement(),
        locationHint: 'Rack A-01',
      );
      await save(tester, label: 'Save changes');
      expect(lastResult!.edit!.locationHint, 'Rack A-01');
    });

    // Regression: the base unit is the variant's `base_uom` at factor 1, not
    // whatever row the server happens to list first. Reading `firstOrNull`
    // priced the form "per KG" with the BAG's ₱270 and PATCHed the BAG row.
    testWidgets('prices and saves the BASE unit when a bag is listed first', (
      tester,
    ) async {
      await openForm(tester, product: multiUnitCement());

      expect(find.text('Selling price per KG'), findsOneWidget);
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

    testWidgets(
      'edit mode shows Utang markup controls and Variants summary without Add selling unit',
      (tester) async {
        await openForm(tester, product: multiUnitCement());

        expect(find.byKey(const ValueKey('credit-markup-kind')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('edit-variants-section')),
          findsOneWidget,
        );
        expect(find.textContaining('Variants (1)'), findsOneWidget);
        expect(find.textContaining('Base unit: KG'), findsOneWidget);
        expect(find.text('Add selling unit'), findsNothing);
      },
    );
  });

  // Phase 2 (2026-11-22): discount exclusions are chosen by the cashier at the till,
  // so the product form no longer shows the Allow discounts switch.
  group('the Allow discounts switch', () {
    testWidgets('is hidden on a new product and defaults allowDiscount to true', (
      tester,
    ) async {
      await openForm(tester);
      await fillBasics(tester);

      expect(find.byKey(const ValueKey('allow-discount-switch')), findsNothing);
      expect(find.text('Allow discounts'), findsNothing);
      await save(tester);

      expect(lastResult!.draft!.allowDiscount, isTrue);
    });

    testWidgets('is hidden on edit and leaves allowDiscount untouched', (
      tester,
    ) async {
      await openForm(tester, product: cementNeverDiscounted());

      expect(find.byKey(const ValueKey('allow-discount-switch')), findsNothing);
      await save(tester, label: 'Save changes');

      expect(
        lastResult!.edit!.allowDiscount,
        isNull,
        reason: 'product edits must not PATCH the legacy allow_discount flag',
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
      if (text != null) {
        final child = text.child;
        return child is Text ? 'button:${child.data}' : 'button:other';
      }
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
      await openForm(tester, size: const Size(1440, 2400));

      // Start the walk at the top of the dialog rather than wherever the last
      // tapped form field left the focus.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      final stops = <String>[];
      for (var i = 0; i < 40; i++) {
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

      expectBefore('field:Product name', 'field:SKU');
      expectBefore('field:SKU', 'field:Base measurement / unit');
      expectBefore('field:Base measurement / unit', 'field:Cost per KG');
      expectBefore('field:Cost per KG', 'field:Selling price per KG');
      expectBefore('field:Selling price per KG', 'field:Stored at');
      expectBefore('field:Stored at', 'button:Cancel');
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
          await tapKey(tester, const ValueKey('tracking-weight'));

          expect(tester.takeException(), isNull);

          // Scrolling to the last field is where a form that only fits at 1.0x
          // gives itself away.
          await tester.ensureVisible(
            find.byKey(const ValueKey('stock-preview')),
          );
          await tester.pumpAndSettle();
          await tester.ensureVisible(find.text('Add product').last);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(find.text('Inventory Tracking'), findsOneWidget);
        },
      );
    }
  });
}
