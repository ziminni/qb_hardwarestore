// K1: the Stock Manager dashboard answers "what needs me", and every control on
// it lands somewhere.
//
// Two historical failures are pinned here.
//
// 1. The panels used to say "Recent stock movements" and render the viewmodel's
//    FLATTENED movements: manual adjustments projected as if they were a
//    movement history. After a normal day of sales and deliveries the panel
//    could still read "No movements recorded." (D2 renamed the screen to Stock
//    adjustments). The panel now reads `InventoryViewmodel.adjustments` itself,
//    so the row carries the server's own adjustment type.
// 2. `InventoryActionButton.onPressed` used to default to `() {}`, so "Export"
//    and "Add product" rendered as live buttons that did nothing. Export is
//    gone (D-04); "Add product" navigates. Every other control added by K1 is
//    pinned the same way: it must ARRIVE somewhere.
//
// The tests drive the LOADED state, because the panels only render after a load
// settles - an unloaded viewmodel shows a spinner instead.

import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/repositories/supplier_repository.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/supplier_service.dart';
import 'package:client/features/dashboard/widget/inventory_dashboard_content.dart';
import 'package:client/features/dashboard/widget/inventory_recent_adjustments_panel.dart';
import 'package:client/features/dashboard/widget/inventory_restock_queue_panel.dart';
import 'package:client/features/dashboard/widget/inventory_waiting_to_receive_panel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import '../../support/phase4_fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// ---------------------------------------------------------------------------
// Fakes: the catalogue, the adjustment log and the purchase orders the
// dashboard reads. No fixture file: the numbers below are the assertions.
// ---------------------------------------------------------------------------

Product _product({required int id, required String name, int threshold = 50}) =>
    Product(
      id: id,
      categoryId: 1,
      categoryName: 'Cement',
      brandId: 1,
      brandName: 'QB',
      baseName: name,
      description: '',
      imageUrl: '',
      isActive: true,
      variants: [
        ProductVariant(
          id: id,
          productId: id,
          baseUomId: 1,
          minStockThreshold: threshold.toDouble(),
          maxStockLevel: 0,
          variantName: '40kg',
          baseUomCode: 'Bag',
          isActive: true,
        ),
      ],
    );

InventoryBatch _batch({required int variantId, required double qty}) =>
    InventoryBatch(
      id: variantId,
      variantId: variantId,
      receiptId: 1,
      initialQty: 100,
      currentQty: qty,
      unitCostLanded: 200,
      markupPercentage: 0,
      batchSellingPrice: 260,
      expirationDate: null,
      createdAt: DateTime(2026, 10, 19),
    );

class _StubProductsRepository extends ProductsRepository {
  _StubProductsRepository({
    List<Product> products = const [],
    List<InventoryBatch> batches = const [],
    this.failure,
  }) : _snapshot = ProductsSnapshot(products: products, batches: batches),
       super(ProductsService());

  final ProductsSnapshot _snapshot;
  final String? failure;

  @override
  Future<ProductsSnapshot> loadCatalogue() async {
    final failure = this.failure;
    if (failure != null) throw ProductsServiceException(failure);
    return _snapshot;
  }
}

class _StubInventoryRepository extends InventoryRepository {
  _StubInventoryRepository([this.adjustments = const []])
    : super(InventoryService());

  final List<StockAdjustment> adjustments;

  @override
  Future<List<SystemAlert>> loadAlerts() async => const [];

  @override
  Future<List<StockAdjustment>> loadAdjustments() async => adjustments;
}

class _StubSupplierRepository extends SupplierRepository {
  _StubSupplierRepository({
    this.suppliers = const [],
    this.purchases = const [],
  });

  final List<Supplier> suppliers;
  final List<PurchaseOrder> purchases;

  // `PurchaseOrderSerializer` sends a supplier ID only, so the viewmodel joins
  // the name from the suppliers it loaded: the stub has to load them too, or
  // every order reads "Supplier not listed".
  @override
  Future<List<Supplier>> fetchSuppliers() async => suppliers;

  @override
  Future<List<PurchaseOrder>> fetchPurchaseOrders() async => purchases;
}

PurchaseOrder _purchase({
  required int id,
  required int supplierId,
  required PurchaseStatus status,
  required double ordered,
  required double received,
  DateTime? expectedDelivery,
}) => PurchaseOrder(
  id: id,
  supplierId: supplierId,
  // Filled by the viewmodel's join, exactly as on the wire.
  supplierName: '',
  orderDate: DateTime(2026, 10, 20),
  expectedDelivery: expectedDelivery,
  status: status,
  createdBy: 'Ana Lopez',
  notes: '',
  items: [
    PurchaseItem(
      productName: '',
      variantName: 'Portland Cement 40kg',
      sku: '',
      quantity: ordered,
      receivedQuantity: received,
      unitCost: 240,
    ),
  ],
);

StockAdjustment _adjustment({
  required int id,
  required int variantId,
  required StockAdjustmentType type,
  required double qty,
  required String remarks,
  required DateTime when,
}) => StockAdjustment(
  id: id,
  variantId: variantId,
  userId: 2,
  adjustmentType: type,
  quantityAdjusted: qty,
  remarks: remarks,
  timestamp: when,
);

/// Three products the dashboard has to reason about: one low, one out, one
/// healthy. The value is deliberate so the money format is assertable.
Future<InventoryViewmodel> _loadedInventory() async {
  final viewmodel = InventoryViewmodel(
    products: _StubProductsRepository(
      products: [
        _product(id: 1, name: 'Portland Cement'),
        _product(id: 2, name: 'Tiles 60x60'),
        _product(id: 3, name: 'Fill Sand'),
      ],
      batches: [
        _batch(variantId: 1, qty: 12),
        _batch(variantId: 2, qty: 0),
        _batch(variantId: 3, qty: 500),
      ],
    ),
    inventory: _StubInventoryRepository([
      _adjustment(
        id: 3,
        variantId: 1,
        type: StockAdjustmentType.damage,
        qty: -2,
        remarks: 'torn bag',
        when: DateTime(2026, 10, 19, 10),
      ),
    ]),
    catalogue: FakeCatalogueRepository(),
  );
  await viewmodel.load();
  return viewmodel;
}

Future<SuppliersPurchasesViewmodel> _loadedPurchases({
  List<PurchaseOrder>? orders,
}) async {
  final viewmodel = SuppliersPurchasesViewmodel(
    repository: _StubSupplierRepository(
      suppliers: const [
        Supplier(
          id: 1,
          companyName: 'Cebu Hardware Trading',
          contactPerson: '',
          phone: '',
          email: '',
          address: '',
        ),
        Supplier(
          id: 2,
          companyName: 'Mindanao Steel',
          contactPerson: '',
          phone: '',
          email: '',
          address: '',
        ),
      ],
      purchases:
          orders ??
          [
            _purchase(
              id: 7,
              supplierId: 1,
              status: PurchaseStatus.ordered,
              ordered: 20,
              received: 0,
              expectedDelivery: DateTime(2026, 10, 25),
            ),
            _purchase(
              id: 8,
              supplierId: 2,
              status: PurchaseStatus.partial,
              ordered: 100,
              received: 40,
              expectedDelivery: DateTime(2026, 10, 28),
            ),
            // Neither of these is waiting for a delivery.
            _purchase(
              id: 9,
              supplierId: 1,
              status: PurchaseStatus.complete,
              ordered: 10,
              received: 10,
            ),
            _purchase(
              id: 10,
              supplierId: 2,
              status: PurchaseStatus.draft,
              ordered: 5,
              received: 0,
            ),
          ],
    ),
  );
  await viewmodel.load();
  return viewmodel;
}

Future<void> _pump(
  WidgetTester tester,
  InventoryViewmodel inventory,
  SuppliersPurchasesViewmodel purchases,
) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: AppRoutes.inventoryDashboard,
    routes: [
      GoRoute(
        path: AppRoutes.inventoryDashboard,
        builder: (_, _) => MultiProvider(
          providers: [
            ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
            ChangeNotifierProvider<SuppliersPurchasesViewmodel>.value(
              value: purchases,
            ),
          ],
          child: const Scaffold(body: InventoryDashboardContent()),
        ),
      ),
      GoRoute(
        path: AppRoutes.inventoryProducts,
        builder: (_, _) => const Text('ARRIVED products'),
      ),
      GoRoute(
        path: AppRoutes.inventoryLowStock,
        builder: (_, _) => const Text('ARRIVED low stock'),
      ),
      GoRoute(
        path: AppRoutes.inventoryReceiving,
        builder: (_, _) => const Text('ARRIVED receiving'),
      ),
      GoRoute(
        path: AppRoutes.inventoryStockMovements,
        builder: (_, _) => const Text('ARRIVED adjustments'),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Export button is gone from the inventory dashboard', (
    tester,
  ) async {
    await _pump(tester, await _loadedInventory(), await _loadedPurchases());
    expect(find.text('Export'), findsNothing);
  });

  testWidgets('Add product button is present', (tester) async {
    await _pump(tester, await _loadedInventory(), await _loadedPurchases());
    expect(find.text('Add product'), findsOneWidget);
  });

  testWidgets('Add product navigates to the products page', (tester) async {
    await _pump(tester, await _loadedInventory(), await _loadedPurchases());
    await tester.tap(find.text('Add product'));
    await tester.pumpAndSettle();
    expect(find.text('ARRIVED products'), findsOneWidget);
  });

  testWidgets('the adjustment panel is named for what it lists (D2)', (
    tester,
  ) async {
    await _pump(tester, await _loadedInventory(), await _loadedPurchases());

    expect(find.text('Recent adjustments'), findsOneWidget);
    expect(find.text('Recent stock movements'), findsNothing);
    // The server's own adjustment type, and the signed delta it carries. The
    // old panel showed a flattened movement with no type at all.
    expect(find.text('Damaged'), findsOneWidget);
    expect(find.text('-2'), findsOneWidget);
    expect(find.textContaining('torn bag'), findsOneWidget);
  });

  testWidgets(
    'waiting to receive lists ordered and part received orders only',
    (tester) async {
      await _pump(tester, await _loadedInventory(), await _loadedPurchases());

      expect(find.text('Waiting to receive'), findsOneWidget);
      expect(find.text('PO-7'), findsOneWidget);
      expect(find.text('Cebu Hardware Trading'), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      // Part received carries what is still owed: 100 ordered, 40 in.
      expect(find.text('PO-8'), findsOneWidget);
      expect(find.text('Part received'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      // A completed order and a draft are not deliveries to expect.
      expect(find.text('PO-9'), findsNothing);
      expect(find.text('PO-10'), findsNothing);
    },
  );

  testWidgets('the tiles count the catalogue and value it at landed cost', (
    tester,
  ) async {
    await _pump(tester, await _loadedInventory(), await _loadedPurchases());

    // Scoped to the tiles: "Low stock" and "Out of stock" are also row badges.
    expect(find.widgetWithText(MetricTile, 'Total products'), findsOneWidget);
    expect(
      find.descendant(
        of: find.widgetWithText(MetricTile, 'Total products'),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
    // 12 x 200 + 0 x 200 + 500 x 200 = 102,400.00
    expect(
      find.descendant(
        of: find.widgetWithText(MetricTile, 'Inventory value'),
        matching: find.text('₱102,400.00'),
      ),
      findsOneWidget,
    );
    expect(find.widgetWithText(MetricTile, 'Low stock'), findsOneWidget);
    expect(find.widgetWithText(MetricTile, 'Out of stock'), findsOneWidget);
  });

  testWidgets('a failed first load is one failure, never also an empty list', (
    tester,
  ) async {
    final inventory = InventoryViewmodel(
      products: _StubProductsRepository(
        failure: 'Cannot connect to the BuildPro server.',
      ),
      inventory: _StubInventoryRepository(),
      catalogue: FakeCatalogueRepository(),
    );
    await inventory.load();
    await _pump(tester, inventory, await _loadedPurchases());

    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    expect(find.textContaining('No products'), findsNothing);
  });

  // Each panel summarises another screen, so each one has to open it: a summary
  // the user cannot act on is a dead end. The three "View all" buttons are
  // identical text, so every finder here is scoped to its own panel.
  Finder viewAllIn(Type panel) =>
      find.descendant(of: find.byType(panel), matching: find.text('View all'));

  testWidgets('the restock queue opens Low stock', (tester) async {
    await _pump(tester, await _loadedInventory(), await _loadedPurchases());

    expect(find.text('View all'), findsNWidgets(3));
    await tester.tap(viewAllIn(InventoryRestockQueuePanel));
    await tester.pumpAndSettle();

    expect(find.text('ARRIVED low stock'), findsOneWidget);
  });

  testWidgets('a restock row opens Low stock, where Reorder lives', (
    tester,
  ) async {
    await _pump(tester, await _loadedInventory(), await _loadedPurchases());

    // The item name also appears in the adjustments panel, so the tap targets
    // the restock row itself.
    await tester.tap(
      find.descendant(
        of: find.byType(InventoryRestockQueuePanel),
        matching: find.text('Portland Cement 40kg'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ARRIVED low stock'), findsOneWidget);
  });

  testWidgets('waiting to receive opens Receiving', (tester) async {
    await _pump(tester, await _loadedInventory(), await _loadedPurchases());

    await tester.tap(viewAllIn(InventoryWaitingToReceivePanel));
    await tester.pumpAndSettle();

    expect(find.text('ARRIVED receiving'), findsOneWidget);
  });

  testWidgets('recent adjustments opens Stock adjustments', (tester) async {
    await _pump(tester, await _loadedInventory(), await _loadedPurchases());

    await tester.tap(viewAllIn(InventoryRecentAdjustmentsPanel));
    await tester.pumpAndSettle();

    expect(find.text('ARRIVED adjustments'), findsOneWidget);
  });

  testWidgets('a failed purchase order read is its own banner, rows intact', (
    tester,
  ) async {
    final purchases = SuppliersPurchasesViewmodel(
      repository: _FailingSupplierRepository(),
    );
    await purchases.load();
    await _pump(tester, await _loadedInventory(), purchases);

    // One failure, named, with its own retry: the purchase order read cannot
    // blank the restock queue, which comes from the catalogue.
    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(InventoryRestockQueuePanel),
        matching: find.text('Portland Cement 40kg'),
      ),
      findsOneWidget,
    );
  });
}

/// Every purchase order read fails, the way an unreachable server does.
class _FailingSupplierRepository extends SupplierRepository {
  @override
  Future<List<Supplier>> fetchSuppliers() async =>
      throw const SupplierServiceException(
        'Cannot connect to the BuildPro server.',
      );

  @override
  Future<List<PurchaseOrder>> fetchPurchaseOrders() async => const [];
}
