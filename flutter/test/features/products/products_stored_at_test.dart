// Phase 5 F4 (decision 18): "Stored at" on the product form.
//
// The pick-up point is a SERVER fact, unlike the device-only shelf note beside
// it. What these tests pin:
//   1. a CREATE sends the id the API actually returned for the row named
//      "Store" — not a hardcoded primary key, and not `first` in the list (a
//      Bodega created before Store must not become the default);
//   2. an EDIT of a product whose location has since been DEACTIVATED keeps it
//      visible and selected, and sends NO stored_at at all — resending it would
//      be refused with INVALID_STORAGE_LOCATION and fail a save the clerk never
//      asked to touch;
//   3. when the location list could not be read, the form refuses to submit
//      instead of quietly writing the server's default for a product nobody
//      chose a place for;
//   4. at 760 px with 1.3x text nothing clips.

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/widgets/products_details_dialog.dart';
import 'package:client/features/products/widgets/products_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

const _categories = [Category(id: 1, name: 'Cement')];
const _brands = [Brand(id: 1, name: 'Holcim')];
const _units = [
  UnitOfMeasure(id: 1, code: 'KG', name: 'Kilogram'),
  UnitOfMeasure(id: 2, code: 'BAG', name: 'Bag', isWhole: true),
];

/// Bodega sorts FIRST. That is the trap: a form that took the first row would
/// file every new product in the bodega.
const _locations = [
  StorageLocation(id: 9, name: 'Bodega'),
  StorageLocation(id: 4, name: 'Store'),
];

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

Future<void> openForm(
  WidgetTester tester, {
  Product? product,
  List<StorageLocation> locations = _locations,
  String? locationError,
  Size size = const Size(1440, 1000),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  lastResult = null;

  await tester.pumpWidget(
    MaterialApp(
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
                    storageLocations: locations,
                    storageLocationError: locationError,
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

Future<void> tapKey(WidgetTester tester, Key key) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// Fills the three steps so `Add product` can be pressed.
Future<void> fillNewProduct(WidgetTester tester) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Product name'),
    'Portland Cement',
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, 'Variant name'),
    '40 kg',
  );
  await tester.enterText(find.byKey(const ValueKey('base-price')), '270');
  await tester.enterText(find.byKey(const ValueKey('reorder-field')), '5');
  await tester.enterText(find.byKey(const ValueKey('max-field')), '100');
  await tester.pumpAndSettle();
}

Future<void> save(WidgetTester tester, {String label = 'Add product'}) async {
  final button = find.widgetWithText(FilledButton, label);
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Product storedAtProduct({
  int? storedAtId = 9,
  String storedAtName = 'Bodega',
}) => product(
  id: 7,
  name: 'Portland Cement',
  variants: [
    variant(
      id: 7,
      productId: 7,
      name: '40 kg',
      baseUomId: 2,
      baseUomCode: 'BAG',
      sellingUoms: const [
        VariantUom(
          id: 70,
          variantId: 7,
          uomId: 2,
          uomCode: 'BAG',
          uomName: 'Bag',
          barcodeQr: '',
          conversionFactor: 1,
          defaultSellingPrice: 270,
        ),
      ],
    ),
  ],
).copyWith(storedAtId: storedAtId, storedAtName: storedAtName);

void main() {
  setUpAll(_loadAppFonts);

  testWidgets('a new product defaults to the row NAMED Store, not the first', (
    tester,
  ) async {
    await openForm(tester);
    await fillNewProduct(tester);
    await save(tester);

    final draft = lastResult?.draft;
    expect(draft, isNotNull, reason: 'the form should have submitted');
    expect(
      draft!.storedAtId,
      4,
      reason:
          'Store is id 4 and sorts second; taking the first row would file '
          'every new product in the Bodega',
    );
    expect(draft.productBody()['stored_at'], 4);
  });

  testWidgets('the clerk may choose another location and it is what is sent', (
    tester,
  ) async {
    await openForm(tester);
    await fillNewProduct(tester);

    await tapKey(tester, const ValueKey('stored-at-picker'));
    await tester.tap(find.text('Bodega').last);
    await tester.pumpAndSettle();
    await save(tester);

    expect(lastResult?.draft?.storedAtId, 9);
    expect(lastResult?.draft?.productBody()['stored_at'], 9);
  });

  testWidgets('editing a product at a DEACTIVATED location keeps it and sends no '
      'stored_at', (tester) async {
    // "Bodega" is no longer offered by the server (deactivated), so it is not in
    // the active list at all — the product still sits there.
    await openForm(
      tester,
      product: storedAtProduct(),
      locations: const [StorageLocation(id: 4, name: 'Store')],
    );

    expect(
      find.text('Bodega (inactive)'),
      findsWidgets,
      reason: 'the product is still in the Bodega; the form must say so',
    );

    await save(tester, label: 'Save changes');

    final edit = lastResult?.edit;
    expect(edit, isNotNull);
    expect(
      edit!.storedAtId,
      isNull,
      reason:
          'an unchanged deactivated location must not be resent: the server '
          'refuses a new assignment with INVALID_STORAGE_LOCATION',
    );
    expect(edit.productBody.containsKey('stored_at'), isFalse);
  });

  testWidgets('moving a product to another location sends the new id', (
    tester,
  ) async {
    await openForm(tester, product: storedAtProduct());

    await tapKey(tester, const ValueKey('stored-at-picker'));
    await tester.tap(find.text('Store').last);
    await tester.pumpAndSettle();
    await save(tester, label: 'Save changes');

    expect(lastResult?.edit?.storedAtId, 4);
    expect(lastResult?.edit?.productBody['stored_at'], 4);
  });

  testWidgets('a failed location read is shown and blocks the create', (
    tester,
  ) async {
    await openForm(
      tester,
      locations: const [],
      locationError: 'The storage locations could not be read.',
    );
    await fillNewProduct(tester);
    await save(tester);

    expect(
      lastResult,
      isNull,
      reason:
          'submitting here would write the server default for a product nobody '
          'chose a place for',
    );
    expect(find.text('The storage locations could not be read.'), findsWidgets);
  });

  testWidgets('760 px at 1.3x text, the stored-at field renders whole', (
    tester,
  ) async {
    await openForm(
      tester,
      product: storedAtProduct(),
      size: const Size(760, 900),
      textScale: 1.3,
    );

    await tester.ensureVisible(find.byKey(const ValueKey('stored-at-picker')));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('stored-at-picker')), findsOneWidget);
    // The device-only shelf note is a different field with different words.
    expect(find.text('Shelf note (this device only)'), findsOneWidget);
    expect(find.text('Not shared with other tills'), findsOneWidget);
  });

  group('product details', () {
    Future<void> openDetails(WidgetTester tester, Product product) async {
      tester.view.physicalSize = const Size(1400, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<InventoryViewmodel>.value(
              value: seededInventory(),
            ),
            ChangeNotifierProvider<AuthViewmodel>.value(
              value: AuthViewmodel(AuthRepository(AuthService())),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(body: ProductsDetailsDialog(product: product)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the server pick-up point as its own row', (
      tester,
    ) async {
      await openDetails(tester, storedAtProduct());

      expect(find.text('Stored at'), findsOneWidget);
      expect(find.text('Bodega'), findsWidgets);
    });

    testWidgets('a legacy product with no location shows no Stored-at row', (
      tester,
    ) async {
      await openDetails(
        tester,
        storedAtProduct(storedAtId: null, storedAtName: ''),
      );

      expect(
        find.text('Stored at'),
        findsNothing,
        reason: 'an empty label must hide the row, not print a blank place',
      );
    });
  });
}
