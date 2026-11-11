// Phase 1d Task 9 (decisions 15-17): the product details dialog shows how a
// product is really sold, and lets a stock role add or remove a selling unit.
//
// Base identity is `variant.baseUomId` at factor 1, NEVER the first row: the
// server may answer [KG, BAG, BOX] or [BAG, KG, ...], and "Remove" must never
// appear on the base unit while appearing on a package that was never used.

import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/widgets/products_details_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

/// Sold by the kilogram (base, measured), the bag of 40 (whole, already sold)
/// and the box of 10 (whole, never used, so removable).
Product packedProduct() => product(
  id: 21,
  name: 'Tile Adhesive',
  categoryName: 'Cement',
  brandName: 'ABC',
  variants: [
    variant(
      id: 210,
      productId: 21,
      name: 'Standard',
      baseUomId: 2,
      baseUomCode: 'KG',
      sellingUoms: [
        variantUom(
          id: 2101,
          variantId: 210,
          uomId: 2,
          uomCode: 'KG',
          uomName: 'Kilogram',
          price: 6.75,
        ),
        variantUom(
          id: 2102,
          variantId: 210,
          uomId: 3,
          uomCode: 'BAG',
          uomName: 'Bag',
          factor: 40,
          price: 270,
          barcode: 'QB000210-2',
          isWhole: true,
          inUse: true,
        ),
        variantUom(
          id: 2103,
          variantId: 210,
          uomId: 4,
          uomCode: 'BOX',
          uomName: 'Box',
          factor: 10,
          price: 67.5,
          barcode: 'QB000210-3',
          isWhole: true,
        ),
      ],
    ),
  ],
);

const units = [
  UnitOfMeasure(id: 2, code: 'KG', name: 'Kilogram'),
  UnitOfMeasure(id: 3, code: 'BAG', name: 'Bag', isWhole: true),
  UnitOfMeasure(id: 4, code: 'BOX', name: 'Box', isWhole: true),
  UnitOfMeasure(id: 5, code: 'PACK', name: 'Pack', isWhole: true),
];

AuthViewmodel authWithRole(String roleCode) {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  auth.user = User(
    id: 1,
    username: 'ana',
    email: 'ana@example.com',
    fullName: 'Ana Cruz',
    role: Role(id: 1, name: roleCode, displayName: roleCode),
  );
  return auth;
}

void main() {
  late FakeProductsRepository repository;
  late InventoryViewmodel inventory;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final product = packedProduct();
    repository = FakeProductsRepository(
      products: [product],
      batches: [batch(id: 1, variantId: 210, qty: 40)],
    );
    inventory = InventoryViewmodel.seeded(
      catalogue: repository,
      inventory: FakeInventoryRepository(),
      catalogueLists: FakeCatalogueRepository(units: units),
      products: [product],
      batches: [batch(id: 1, variantId: 210, qty: 40)],
      units: units,
    );
  });

  Future<void> openDetails(WidgetTester tester, String roleCode) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
          ChangeNotifierProvider<AuthViewmodel>.value(
            value: authWithRole(roleCode),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      ProductsDetailsDialog(product: packedProduct()),
                ),
                child: const Text('open details'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open details'));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('each selling unit shows factor, price, code and whole/measured '
      'in words', (tester) async {
    await openDetails(tester, 'inventory');

    expect(find.textContaining('KG'), findsWidgets);
    expect(find.textContaining('×40'), findsOneWidget);
    expect(find.textContaining('₱270.00'), findsOneWidget);
    expect(find.textContaining('₱6.75'), findsOneWidget);
    expect(
      find.textContaining('Whole'),
      findsWidgets,
      reason: 'the bag and box are counted in ones; the word says so',
    );
    expect(
      find.textContaining('Measured'),
      findsWidgets,
      reason: 'the kilogram is sold in fractions; the word says so',
    );
    expect(find.textContaining('QB000210-2'), findsOneWidget);
  });

  testWidgets('a cashier gets no Add selling unit and no Remove', (
    tester,
  ) async {
    await openDetails(tester, 'pos');

    expect(find.text('Add selling unit'), findsNothing);
    expect(find.text('Remove'), findsNothing);
    expect(find.text('Edit code'), findsNothing);
  });

  testWidgets('Remove is offered only for an unused NON-base unit', (
    tester,
  ) async {
    await openDetails(tester, 'inventory');

    expect(find.byKey(const ValueKey('remove-unit-2103')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('remove-unit-2101')),
      findsNothing,
      reason: 'the factor-1 base unit can never be removed',
    );
    expect(
      find.byKey(const ValueKey('remove-unit-2102')),
      findsNothing,
      reason: 'a unit already sold stays, its price and code editable',
    );
    expect(find.byKey(const ValueKey('add-selling-unit-210')), findsOneWidget);
  });

  testWidgets('Add selling unit posts the same row fields and reloads', (
    tester,
  ) async {
    await openDetails(tester, 'inventory');
    final loadsBefore = repository.loadCount;

    await tapVisible(
      tester,
      find.byKey(const ValueKey('add-selling-unit-210')),
    );
    await tapVisible(tester, find.byKey(const ValueKey('add-unit-0')));
    await tester.tap(find.text('Pack (PACK)').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('add-factor-0')), '5');
    await tester.enterText(find.byKey(const ValueKey('add-price-0')), '30');
    await tapVisible(tester, find.text('Add unit'));

    final created = repository.createdUnits.single;
    expect(created.variantId, 210);
    expect(created.unit.uomId, 5);
    expect(created.unit.conversionFactor, 5);
    expect(created.unit.sellingPrice, 30);
    expect(repository.loadCount, loadsBefore + 1);
    expect(
      find.byKey(const ValueKey('add-factor-0')),
      findsNothing,
      reason: 'a saved unit closes the dialog',
    );
  });

  testWidgets('the add form mirrors the server: no base unit, no duplicate, '
      'no fractional-factor typo, no negative price', (tester) async {
    await openDetails(tester, 'inventory');
    await tapVisible(
      tester,
      find.byKey(const ValueKey('add-selling-unit-210')),
    );

    await tapVisible(tester, find.byKey(const ValueKey('add-unit-0')));
    await tester.tap(find.text('Kilogram (KG)').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('add-factor-0')), '1');
    await tester.enterText(find.byKey(const ValueKey('add-price-0')), '-5');
    await tapVisible(tester, find.text('Add unit'));

    expect(find.text('This unit is already used.'), findsOneWidget);
    expect(find.text('A unit of 1 KG is the base unit.'), findsOneWidget);
    expect(find.text('The price cannot be negative.'), findsOneWidget);
    expect(repository.createdUnits, isEmpty);
  });

  testWidgets('removing asks first, names the unit and says it cannot be '
      'undone', (tester) async {
    await openDetails(tester, 'inventory');
    final loadsBefore = repository.loadCount;

    await tapVisible(tester, find.byKey(const ValueKey('remove-unit-2103')));

    expect(find.text('Remove Box (10 KG)?'), findsOneWidget);
    expect(find.text('This cannot be undone.'), findsOneWidget);

    await tapVisible(tester, find.text('Remove unit'));

    expect(repository.deletedUnitIds, [2103]);
    expect(repository.loadCount, loadsBefore + 1);
    expect(
      find.byKey(const ValueKey('remove-unit-2103')),
      findsNothing,
      reason: 'the reloaded list no longer holds the removed unit',
    );
  });

  testWidgets('a server refusal keeps the list intact and reloads it', (
    tester,
  ) async {
    repository.deleteError =
        'This selling unit has already been sold, held or requested, so it '
        'cannot be removed. Its price and code stay editable.';
    await openDetails(tester, 'inventory');
    final loadsBefore = repository.loadCount;

    await tapVisible(tester, find.byKey(const ValueKey('remove-unit-2103')));
    await tapVisible(tester, find.text('Remove unit'));

    expect(
      find.textContaining('cannot be removed'),
      findsOneWidget,
      reason: 'the server sentence is shown where the action was taken',
    );
    expect(
      find.byKey(const ValueKey('remove-unit-2103')),
      findsOneWidget,
      reason: 'nothing was written, so the unit is still there',
    );
    expect(
      repository.loadCount,
      loadsBefore + 1,
      reason: 'the refusal means the dialog was out of date: reload it',
    );
  });

  testWidgets('the storage location is shown as this device only', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'stock_location_hints': '{"210":"Rack A-01"}',
    });
    await inventory.loadLocationHints();
    await openDetails(tester, 'inventory');

    expect(find.textContaining('Rack A-01'), findsOneWidget);
    expect(find.text('Saved on this device only'), findsOneWidget);
  });
}
