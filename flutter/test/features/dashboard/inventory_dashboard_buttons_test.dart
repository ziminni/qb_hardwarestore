// Stocker-workflow phase 4: the dashboard's action buttons were dead.
//
// `InventoryActionButton.onPressed` defaults to `() {}`, so "Export" and
// "Add product" rendered as clickable buttons that did nothing, and no export
// endpoint exists anywhere in the client or the API - a button that can never
// work. Decision D-04: Export is deleted, "Add product" navigates to the live
// Products page.
//
// The test drives the LOADED state, because that is the only state in which the
// action row renders - an unloaded viewmodel shows a spinner instead, and an
// assertion against the spinner would pass without ever seeing a button.

import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/dashboard/widget/inventory_dashboard_content.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class _EmptyProductsRepository extends ProductsRepository {
  _EmptyProductsRepository() : super(ProductsService());

  @override
  Future<ProductsSnapshot> loadCatalogue() async =>
      const ProductsSnapshot(products: [], batches: []);
}

class _EmptyInventoryRepository extends InventoryRepository {
  _EmptyInventoryRepository() : super(InventoryService());

  @override
  Future<List<SystemAlert>> loadAlerts() async => const [];

  @override
  Future<List<StockAdjustment>> loadAdjustments() async => const [];
}

Future<InventoryViewmodel> _loadedInventory() async {
  final viewmodel = InventoryViewmodel(
    products: _EmptyProductsRepository(),
    inventory: _EmptyInventoryRepository(),
  );
  await viewmodel.load();
  return viewmodel;
}

Future<void> _pump(WidgetTester tester, InventoryViewmodel viewmodel) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/inventory/dashboard',
    routes: [
      GoRoute(
        path: AppRoutes.inventoryDashboard,
        builder: (_, _) => ChangeNotifierProvider<InventoryViewmodel>.value(
          value: viewmodel,
          child: const Scaffold(body: InventoryDashboardContent()),
        ),
      ),
      GoRoute(
        path: AppRoutes.inventoryProducts,
        builder: (_, _) => const Text('ARRIVED products'),
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
    await _pump(tester, await _loadedInventory());
    expect(find.text('Export'), findsNothing);
  });

  testWidgets('Add product button is present', (tester) async {
    await _pump(tester, await _loadedInventory());
    expect(find.text('Add product'), findsOneWidget);
  });

  testWidgets('Add product navigates to the products page', (tester) async {
    await _pump(tester, await _loadedInventory());
    await tester.tap(find.text('Add product'));
    await tester.pumpAndSettle();
    expect(find.text('ARRIVED products'), findsOneWidget);
  });
}
