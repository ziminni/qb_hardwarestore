// Phase 1 (decision 12 + decision 07): the products page must render its four
// states through the one shared AsyncView, and it must not show the MOCK
// catalogue while the real one is being fetched.
//
// Honest note: the page was wired BEFORE this test existed, so this locks the
// behaviour rather than driving it. Recorded in the ledger as a TDD deviation.

import 'dart:async';

import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:client/features/products/views/products_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

ProductsSnapshot _apiSnapshot() => ProductsSnapshot(
  products: [
    Product(
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
          minStockThreshold: 5,
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
    ),
  ],
  batches: [
    InventoryBatch(
      id: 6,
      variantId: 8,
      receiptId: 6,
      initialQty: 100,
      currentQty: 100,
      unitCostLanded: 180,
      markupPercentage: 0,
      batchSellingPrice: 180,
      expirationDate: null,
      createdAt: null,
    ),
  ],
);

/// Task 2 (decision 13) made load() also reach the inventory endpoints, so this
/// must be supplied or the store would reach for a Dio that no test initialises.
class _FakeInventoryRepository extends InventoryRepository {
  _FakeInventoryRepository() : super(InventoryService());
  @override
  Future<List<SystemAlert>> loadAlerts() async => const [];
  @override
  Future<List<StockAdjustment>> loadAdjustments() async => const [];
}

class _FakeProductsRepository extends ProductsRepository {
  _FakeProductsRepository({this.snapshot}) : super(ProductsService());

  ProductsSnapshot? snapshot;
  ProductsServiceException? error;
  int calls = 0;
  Future<void>? gate;

  @override
  Future<ProductsSnapshot> loadCatalogue() async {
    calls++;
    if (gate != null) await gate;
    final failure = error;
    if (failure != null) throw failure;
    return snapshot!;
  }
}

void main() {
  late _FakeProductsRepository products;
  late _FakeInventoryRepository inventory;

  setUp(() {
    products = _FakeProductsRepository(snapshot: _apiSnapshot());
    inventory = _FakeInventoryRepository();
  });

  Future<void> pumpPage(WidgetTester tester, InventoryViewmodel store) async {
    // The shared skeleton and its toolbar are built for a wide desktop shell;
    // under the default 800x600 test surface, and even at 1600, the toolbar Row
    // overflows (a PRE-EXISTING overflow in products_toolbar.dart, not caused by
    // this change). Give the test a real window instead of weakening widgets.
    tester.view.physicalSize = const Size(2560, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // `InventorySkeletonLayout` is the shared app shell and reads AuthViewmodel
    // for the signed-in identity, so the page cannot render without it.
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>(
            create: (_) => AuthViewmodel(AuthRepository(AuthService())),
          ),
          ChangeNotifierProvider<InventoryViewmodel>.value(value: store),
          ChangeNotifierProvider<ProductTrackingViewmodel>(
            create: (_) => ProductTrackingViewmodel(),
          ),
        ],
        child: const MaterialApp(home: ProductsPage()),
      ),
    );
  }

  testWidgets('shows a loading state, NOT the mock catalogue, before the first '
      'load finishes', (tester) async {
    // The store still holds 12 mock products at this point. If the page rendered
    // them, a user would see real-looking data that is not real and then watch it
    // change. The spinner must cover that window.
    final store = InventoryViewmodel(products: products, inventory: inventory);
    final gate = Completer<void>();
    products.gate = gate.future;

    await pumpPage(tester, store);
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Portland Cement'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('renders the loaded catalogue', (tester) async {
    final store = InventoryViewmodel(products: products, inventory: inventory);

    await pumpPage(tester, store);
    await tester.pumpAndSettle();

    expect(find.text('Circuit Breaker'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('a failed load shows the error and Retry re-runs the fetch', (
    tester,
  ) async {
    final store = InventoryViewmodel(products: products, inventory: inventory);
    products.error = const ProductsServiceException('Cannot connect.');

    await pumpPage(tester, store);
    await tester.pumpAndSettle();

    expect(find.text('Cannot connect.'), findsOneWidget);
    expect(find.text('Circuit Breaker'), findsNothing);
    expect(products.calls, 1);

    products.error = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(products.calls, 2);
    expect(find.text('Circuit Breaker'), findsWidgets);
  });
}
