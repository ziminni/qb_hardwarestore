// Phase 2 (decision 13, rule 1): the low-stock screen READS the server's alerts
// and stops deriving its own list.
//
// The test that matters is the second one. It sets up a variant that is genuinely
// BELOW its threshold while the server has raised NO alert for it, and asserts the
// screen shows nothing. That is the deliberate consequence of one authority: the
// screen reflects what the server alerted, not what the client could compute.
// Before this change the client's own predicate decided, which is how the list and
// the alert screen could contradict each other about the same row.

import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_low_stock_page.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/status_badge.dart';
import '../../support/phase4_fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Product _product({double threshold = 20}) => Product(
  id: 6,
  categoryId: 3,
  categoryName: 'Electrical',
  brandId: 1,
  brandName: 'Omni',
  baseName: 'Circuit Breaker',
  description: '',
  imageUrl: '',
  isActive: true,
  variants: [
    ProductVariant(
      productId: 6,
      baseUomId: 2,
      maxStockLevel: 0,
      id: 8,
      variantName: '20A 1-pole',
      baseUomCode: 'PC',
      isActive: true,
      minStockThreshold: threshold,
      sellingUoms: [
        VariantUom(
          id: 8,
          variantId: 8,
          uomId: 2,
          uomCode: 'PC',
          uomName: 'Piece',
          barcodeQr: '',
          conversionFactor: 1,
          defaultSellingPrice: 315,
        ),
      ],
    ),
  ],
);

ProductsSnapshot _catalogue({double qty = 3}) => ProductsSnapshot(
  products: [_product()],
  batches: [
    InventoryBatch(
      id: 8,
      variantId: 8,
      receiptId: 8,
      initialQty: qty,
      currentQty: qty,
      unitCostLanded: 180,
      markupPercentage: 0,
      batchSellingPrice: 180,
      expirationDate: null,
      createdAt: null,
    ),
  ],
);

SystemAlert _alert({bool resolved = false}) => SystemAlert(
  id: 1,
  type: SystemAlertType.lowStock,
  variantId: 8,
  message: 'Circuit Breaker 20A 1-pole is low.',
  isResolved: resolved,
  createdAt: null,
);

class _FakeProductsRepository extends ProductsRepository {
  _FakeProductsRepository(this.snapshot) : super(ProductsService());
  final ProductsSnapshot snapshot;
  @override
  Future<ProductsSnapshot> loadCatalogue() async => snapshot;
}

class _FakeInventoryRepository extends InventoryRepository {
  _FakeInventoryRepository() : super(InventoryService());
  List<SystemAlert> alerts = [];
  @override
  Future<List<SystemAlert>> loadAlerts() async => alerts;
  @override
  Future<List<StockAdjustment>> loadAdjustments() async => const [];
}

/// Three alerted variants with different urgency: Tiles are out of stock, PVC
/// Pipe sits at a fifth of its level and Portland Cement at two fifths. The
/// alerts arrive in the WRONG order (cement, tiles, pvc), so a screen that keeps
/// the server's order fails the ordering test below.
List<Product> _threeProducts() => [
  product(
    id: 1,
    name: 'Portland Cement',
    variants: [variant(id: 1, productId: 1, name: '40kg', threshold: 30)],
  ),
  product(
    id: 2,
    name: 'Tiles 60x60',
    variants: [variant(id: 2, productId: 2, name: 'Glossy', threshold: 40)],
  ),
  product(
    id: 3,
    name: 'PVC Pipe',
    variants: [variant(id: 3, productId: 3, name: '1/2 inch', threshold: 10)],
  ),
];

/// 12 of 30 and 2 of 10 on hand; nothing at all for the Tiles.
List<InventoryBatch> _threeBatches() => [
  batch(id: 1, variantId: 1, qty: 12),
  batch(id: 3, variantId: 3, qty: 2),
];

List<SystemAlert> _threeAlerts() => [
  alert(id: 11, variantId: 1),
  alert(id: 12, variantId: 2, type: SystemAlertType.outOfStock),
  alert(id: 13, variantId: 3),
];

InventoryViewmodel _urgencyStore({
  List<SystemAlert>? alerts,
  List<Product>? products,
  List<InventoryBatch>? batches,
}) => InventoryViewmodel(
  products: FakeProductsRepository(
    products: products ?? _threeProducts(),
    batches: batches ?? _threeBatches(),
  ),
  inventory: FakeInventoryRepository(alerts: alerts ?? _threeAlerts()),
  catalogue: FakeCatalogueRepository(),
);

void main() {
  Future<void> pumpPage(
    WidgetTester tester,
    InventoryViewmodel store, {
    Size size = const Size(2560, 1600),
  }) async {
    // The shared shell reads AuthViewmodel, and the skeleton asserts under the
    // default 800x600 surface — same harness notes as the products page test.
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>(
            create: (_) => AuthViewmodel(AuthRepository(AuthService())),
          ),
          ChangeNotifierProvider<InventoryViewmodel>.value(value: store),
        ],
        child: const MaterialApp(home: InventoryLowStockPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a low variant shows where its stock sits', (tester) async {
    // Phase 9 F1 (decision 21 §4): the threshold stays on the TOTAL, and the row
    // says which shelf holds what — "Store 3 · Bodega 2" — so a reorder decision
    // can see that the shortfall is not evenly spread.
    final store = InventoryViewmodel(
      products: FakeProductsRepository(
        products: [_product()],
        batches: [batch(id: 8, variantId: 8, qty: 5)],
        stockOnHand: [
          onHand(variantId: 8, qty: 3),
          onHand(
            variantId: 8,
            qty: 2,
            locationId: 2,
            locationName: 'Bodega',
            isHome: false,
          ),
        ],
      ),
      inventory: FakeInventoryRepository(alerts: [_alert()]),
      catalogue: FakeCatalogueRepository(),
    );
    await store.load();

    await pumpPage(tester, store);

    expect(find.text('Store 3 · Bodega 2'), findsWidgets);
  });

  testWidgets('lists the variant the SERVER alerted', (tester) async {
    final inventory = _FakeInventoryRepository()..alerts = [_alert()];
    final store = InventoryViewmodel(
      products: _FakeProductsRepository(_catalogue()),
      inventory: inventory,
      catalogue: FakeCatalogueRepository(),
    );
    await store.load();

    await pumpPage(tester, store);

    expect(find.textContaining('20A 1-pole'), findsWidgets);
  });

  testWidgets('does NOT list a low variant the server has not alerted', (
    tester,
  ) async {
    // Stock 3 against a threshold of 20 — plainly below — but no alert exists.
    // The screen must show nothing, because the server is the authority. This is
    // the behaviour decision 13 accepted, and the reason it is worth a test is
    // that it is the OPPOSITE of what the old derivation did.
    final inventory = _FakeInventoryRepository();
    final store = InventoryViewmodel(
      products: _FakeProductsRepository(_catalogue(qty: 3)),
      inventory: inventory,
      catalogue: FakeCatalogueRepository(),
    );
    await store.load();

    await pumpPage(tester, store);

    expect(
      find.textContaining('20A 1-pole'),
      findsNothing,
      reason: 'membership comes from /alerts/, not from a client predicate',
    );
  });

  testWidgets('ignores a RESOLVED alert', (tester) async {
    final inventory = _FakeInventoryRepository()
      ..alerts = [_alert(resolved: true)];
    final store = InventoryViewmodel(
      products: _FakeProductsRepository(_catalogue()),
      inventory: inventory,
      catalogue: FakeCatalogueRepository(),
    );
    await store.load();

    await pumpPage(tester, store);

    expect(find.textContaining('20A 1-pole'), findsNothing);
  });

  // ------------------------------------------------- the urgency of the list

  testWidgets(
    'sorts out of stock first, then the lowest stock against its level',
    (tester) async {
      final store = _urgencyStore();
      await store.load();

      await pumpPage(tester, store);

      // Read the rendered order off the screen, not off a sorted list: the point
      // is what the reader sees first.
      final outOfStock = tester.getTopLeft(find.text('Tiles 60x60')).dy;
      final lowest = tester.getTopLeft(find.text('PVC Pipe')).dy;
      final highest = tester.getTopLeft(find.text('Portland Cement')).dy;

      expect(
        outOfStock,
        lessThan(lowest),
        reason: 'nothing left beats 2 of 10',
      );
      expect(lowest, lessThan(highest), reason: '2 of 10 beats 12 of 30');
    },
  );

  testWidgets('says the shortage in words with the shared StatusBadge', (
    tester,
  ) async {
    final store = _urgencyStore();
    await store.load();

    await pumpPage(tester, store);

    expect(find.byType(StatusBadge), findsNWidgets(3));
    expect(
      find.widgetWithText(StatusBadge, 'Out of stock'),
      findsOneWidget,
      reason: 'a tinted pill alone is unreadable to a color blind reader',
    );
    expect(find.widgetWithText(StatusBadge, 'Low stock'), findsNWidgets(2));
  });

  testWidgets('reads a large quantity with its thousands grouped', (
    tester,
  ) async {
    // A seven digit level, so a column that prints 1199000 instead of 1,199,000
    // is visible in the test rather than only on a big catalogue.
    final store = _urgencyStore(
      products: [
        product(
          id: 9,
          name: 'Fill Sand',
          variants: [
            variant(id: 9, productId: 9, name: 'Screened', threshold: 1200000),
          ],
        ),
      ],
      batches: [batch(id: 9, variantId: 9, qty: 1199000)],
      alerts: [alert(id: 90, variantId: 9)],
    );
    await store.load();

    await pumpPage(tester, store);

    expect(find.text('1,199,000'), findsOneWidget);
    expect(
      find.text('left of 1,200,000'),
      findsOneWidget,
      reason: 'a seven digit level keeps its thousands separators too',
    );
  });

  // ------------------------------------------------------------- the filters

  testWidgets('the Out of stock chip hides everything else', (tester) async {
    final store = _urgencyStore();
    await store.load();

    await pumpPage(tester, store);
    await tester.tap(
      find.descendant(
        of: find.byType(FilterBar),
        matching: find.text('Out of stock'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Tiles 60x60'), findsOneWidget);
    expect(find.text('PVC Pipe'), findsNothing);
    expect(find.text('Portland Cement'), findsNothing);
  });

  testWidgets('the Low stock chip uses the same words as the row badge', (
    tester,
  ) async {
    // FX5: the chip said "Low" while every badge and every other screen said
    // "Low stock". One state, one word.
    final store = _urgencyStore();
    await store.load();

    await pumpPage(tester, store);
    final chip = find.descendant(
      of: find.byType(FilterBar),
      matching: find.text('Low stock'),
    );
    expect(chip, findsOneWidget);

    await tester.tap(chip);
    await tester.pumpAndSettle();

    expect(find.text('Portland Cement'), findsOneWidget);
    expect(find.text('PVC Pipe'), findsOneWidget);
    expect(
      find.text('Tiles 60x60'),
      findsNothing,
      reason: 'the out-of-stock row belongs to the other chip',
    );
  });

  testWidgets('a filter that hides every row says so', (tester) async {
    // Two low rows and no out-of-stock one: the Out of stock chip empties the
    // list. The copy has to name the filter, not claim the server is quiet.
    final store = _urgencyStore(alerts: _threeAlerts().sublist(0, 1));
    await store.load();

    await pumpPage(tester, store);
    await tester.tap(
      find.descendant(
        of: find.byType(FilterBar),
        matching: find.text('Out of stock'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('No low-stock products match this search.'),
      findsOneWidget,
    );
  });

  testWidgets('nothing alerted reads as the server having flagged nothing', (
    tester,
  ) async {
    final store = _urgencyStore(alerts: const []);
    await store.load();

    await pumpPage(tester, store);

    expect(find.text('No low-stock alerts right now.'), findsOneWidget);
  });

  // --------------------------------------------------------------- the widths

  testWidgets('a 760 px window gets cards, a 1100 px one a table', (
    tester,
  ) async {
    final store = _urgencyStore();
    await store.load();

    await pumpPage(tester, store, size: const Size(760, 900));
    expect(find.byKey(const ValueKey('DataPanel.cards')), findsOneWidget);
    expect(find.byKey(const ValueKey('DataPanel.table')), findsNothing);

    await pumpPage(tester, store, size: const Size(1100, 900));
    expect(find.byKey(const ValueKey('DataPanel.table')), findsOneWidget);
    expect(find.byKey(const ValueKey('DataPanel.cards')), findsNothing);
  });
}
