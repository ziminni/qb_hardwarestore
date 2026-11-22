import 'package:client/data/models/product.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/views/products_page.dart';
import 'package:client/features/products/widgets/price_table_dialog.dart';
import 'package:client/features/products/widgets/products_details_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

List<Product> _priceCatalogue() => [
  product(
    id: 1,
    name: 'Common Nails',
    categoryName: 'Fasteners',
    brandName: 'APO',
    variants: [
      variant(
        id: 101,
        productId: 1,
        name: 'Per Box',
        baseUomId: 1,
        baseUomCode: 'BOX',
        sellingUoms: [
          variantUom(
            id: 1001,
            variantId: 101,
            uomId: 1,
            uomCode: 'BOX',
            uomName: 'Box',
            price: 500,
            barcode: 'QB000101-1',
          ),
        ],
      ),
      variant(
        id: 102,
        productId: 1,
        name: 'Per Piece',
        baseUomId: 2,
        baseUomCode: 'PC',
        sellingUoms: [
          variantUom(
            id: 1002,
            variantId: 102,
            uomId: 2,
            uomCode: 'PC',
            uomName: 'Piece',
            price: 2.50,
            barcode: 'QB000102-8',
          ),
        ],
      ),
    ],
  ),
  product(
    id: 2,
    name: 'Portland Cement',
    categoryName: 'Cement',
    brandName: 'Holcim',
    variants: [
      variant(
        id: 201,
        productId: 2,
        name: '40kg',
        baseUomId: 3,
        baseUomCode: 'BAG',
        sellingUoms: [
          variantUom(
            id: 2001,
            variantId: 201,
            uomId: 3,
            uomCode: 'BAG',
            uomName: 'Bag',
            price: 270,
            barcode: 'QB000201-5',
          ),
        ],
      ),
    ],
  ),
];

User _userWithRole(String role) => User(
  id: 1,
  username: 'manager',
  email: 'mgr@qb.ph',
  fullName: 'Ana Cruz',
  role: Role(id: 1, name: role, displayName: role),
);

void main() {
  late FakeProductsRepository repository;
  late InventoryViewmodel inventory;

  setUp(() {
    final products = _priceCatalogue();
    final batches = [
      batch(id: 1, variantId: 101, qty: 20, cost: 380),
      batch(id: 2, variantId: 102, qty: 500, cost: 1.50),
      batch(id: 3, variantId: 201, qty: 80, cost: 235),
    ];
    repository = FakeProductsRepository(products: products, batches: batches);
    inventory = InventoryViewmodel.seeded(
      catalogue: repository,
      inventory: FakeInventoryRepository(),
      catalogueLists: FakeCatalogueRepository(),
      products: products,
      batches: batches,
      stockOnHand: onHandFromBatches(batches),
    );
  });

  Future<void> openPriceTable(
    WidgetTester tester, {
    Size size = const Size(1440, 900),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
          ChangeNotifierProvider<AuthViewmodel>(
            create: (_) =>
                AuthViewmodel(AuthRepository(AuthService()))
                  ..user = _userWithRole('inventory'),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const PriceTableDialog(),
                ),
                child: const Text('open price table'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open price table'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'displays every product, variant, selling unit, cost, and selling price',
    (tester) async {
      await openPriceTable(tester);

      expect(find.text('Selling Price Table'), findsOneWidget);
      expect(find.text('Showing 3 of 3 selling prices'), findsOneWidget);
      expect(find.text('Common Nails'), findsNWidgets(2));
      expect(find.textContaining('Per Box'), findsOneWidget);
      expect(find.textContaining('Per Piece'), findsOneWidget);
      expect(find.text('Portland Cement'), findsOneWidget);
      expect(find.text('₱380.00'), findsOneWidget);
      expect(find.text('₱235.00'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search and category filters narrow the price table rows', (
    tester,
  ) async {
    await openPriceTable(tester);

    await tester.enterText(
      find.byKey(const ValueKey('price-table-search')),
      'Per Piece',
    );
    await tester.pumpAndSettle();

    expect(find.text('Showing 1 of 3 selling prices'), findsOneWidget);
    expect(find.byKey(const ValueKey('price-row-1002')), findsOneWidget);
    expect(find.byKey(const ValueKey('price-row-2001')), findsNothing);
  });

  testWidgets('modifying one row price and saving PATCHes that selling unit', (
    tester,
  ) async {
    await openPriceTable(tester);
    final loadsBefore = repository.loadCount;

    await tester.enterText(
      find.byKey(const ValueKey('price-input-1002')),
      '3.25',
    );
    await tester.pumpAndSettle();

    expect(find.text('Save all changes (1)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('price-save-1002')));
    await tester.pumpAndSettle();

    final patch = repository.sellingUnitPatches.single;
    expect(patch.unitId, 1002);
    expect(patch.body['default_selling_price'], '3.25');
    expect(patch.body['credit_markup_kind'], 'NONE');
    expect(repository.loadCount, loadsBefore + 1);
    expect(find.text('All prices saved'), findsOneWidget);
  });

  testWidgets('modifying multiple rows and tapping Save all saves them in bulk', (
    tester,
  ) async {
    await openPriceTable(tester);
    final loadsBefore = repository.loadCount;

    await tester.enterText(
      find.byKey(const ValueKey('price-input-1001')),
      '525',
    );
    await tester.enterText(
      find.byKey(const ValueKey('price-input-2001')),
      '285.50',
    );
    await tester.pumpAndSettle();

    expect(find.text('Save all changes (2)'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('price-table-save-all')));
    await tester.pumpAndSettle();

    expect(repository.sellingUnitPatches.length, 2);
    final byId = {
      for (final p in repository.sellingUnitPatches) p.unitId: p.body,
    };
    expect(byId[1001]?['default_selling_price'], '525.00');
    expect(byId[2001]?['default_selling_price'], '285.50');
    expect(repository.loadCount, loadsBefore + 1);
    expect(find.text('Saved 2 selling prices.'), findsOneWidget);
  });

  testWidgets('rejects negative selling price without sending a PATCH', (
    tester,
  ) async {
    await openPriceTable(tester);

    await tester.enterText(
      find.byKey(const ValueKey('price-input-1001')),
      '-10',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('price-save-1001')));
    await tester.pumpAndSettle();

    expect(find.text('Price cannot be negative.'), findsOneWidget);
    expect(repository.sellingUnitPatches, isEmpty);
  });

  testWidgets('fits a narrow 760 px window without overflow', (tester) async {
    await openPriceTable(tester, size: const Size(760, 900));

    expect(find.text('Selling Price Table'), findsOneWidget);
    expect(find.byKey(const ValueKey('price-row-1001')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ProductsPage opens Price Table for inventory roles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
          ChangeNotifierProvider<AuthViewmodel>(
            create: (_) =>
                AuthViewmodel(AuthRepository(AuthService()))
                  ..user = _userWithRole('inventory'),
          ),
        ],
        child: const MaterialApp(home: ProductsPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('open-price-table')));
    await tester.pumpAndSettle();

    expect(find.byType(PriceTableDialog), findsOneWidget);
    expect(find.text('Selling Price Table'), findsOneWidget);
  });

  testWidgets('Product Details Edit price updates any variant selling unit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final nails = _priceCatalogue().first;
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
          ChangeNotifierProvider<AuthViewmodel>(
            create: (_) =>
                AuthViewmodel(AuthRepository(AuthService()))
                  ..user = _userWithRole('inventory'),
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => ProductsDetailsDialog(product: nails),
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

    final editBtn = find.byKey(const ValueKey('edit-price-unit-1002'));
    await tester.ensureVisible(editBtn);
    await tester.pumpAndSettle();
    await tester.tap(editBtn);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('edit-unit-price-field')),
      '3.50',
    );
    await tester.tap(find.byKey(const ValueKey('edit-unit-price-save')));
    await tester.pumpAndSettle();

    expect(repository.sellingUnitPatches.single.unitId, 1002);
    expect(
      repository.sellingUnitPatches.single.body['default_selling_price'],
      '3.50',
    );
    expect(find.textContaining('₱3.50'), findsOneWidget);
  });
}
