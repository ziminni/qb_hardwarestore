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

void main() {
  Future<void> pumpPage(WidgetTester tester, InventoryViewmodel store) async {
    // The shared shell reads AuthViewmodel, and the skeleton asserts under the
    // default 800x600 surface — same harness notes as the products page test.
    tester.view.physicalSize = const Size(2560, 1600);
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
}
