// Phase 4 Task 4 — provider placement, proved through the REAL router.
//
// The Low-stock screen gained two collaborators: the app-scoped
// `SuppliersPurchasesViewmodel` (to create a purchase order from a Reorder) and
// `AuthViewmodel` (to decide whether the role may resolve an alert). Both live in
// `main.dart`'s MultiProvider, so the ROUTE must work with exactly that set — a
// page-scoped provider would blow up here, which is the failure mode Phase 3 hit
// with the shift dialog (`ProviderNotFoundException`).
//
// This drives `AppRoutes.createRouter` and `go()`s to the route instead of
// constructing the page by hand, so a missing provider or a broken route is a test
// failure rather than a crash in the browser.

import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/supplier_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/supplier_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_low_stock_page.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/suppliers/widgets/purchases_form_dialog.dart';
import 'package:client/routes/routes.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/phase4_fakes.dart';

/// Answers every request with a connection error, so anything the route tries to
/// fetch fails fast instead of hanging on DNS (`late final dio` is per-process).
class _OfflineAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async => ResponseBody.fromString('{"detail":"offline"}', 503);

  @override
  void close({bool force = false}) {}
}

class _StubSupplierRepository extends SupplierRepository {
  _StubSupplierRepository() : super(service: SupplierService());

  @override
  Future<List<Supplier>> fetchSuppliers() async => const [
    Supplier(
      id: 3,
      companyName: 'Cebu Steel Works',
      contactPerson: '',
      phone: '',
      email: '',
      address: '',
    ),
  ];

  @override
  Future<List<PurchaseOrder>> fetchPurchaseOrders() async => const [];
}

AuthViewmodel _stockManager() {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  auth
    ..user = const User(
      id: 1,
      username: 'stock',
      email: 'stock@qb.ph',
      fullName: 'Ana Lopez',
      role: Role(id: 4, name: 'inventory', displayName: 'Stock Manager'),
    )
    ..isInitializing = false;
  return auth;
}

void main() {
  test('the inventory role is allowed onto the low-stock route', () {
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: 'inventory',
        location: AppRoutes.inventoryLowStock,
      ),
      isNull,
    );
  });

  testWidgets('the real router opens Low stock with main.dart\'s providers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(3200, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    ApiClient.instance.init();
    ApiClient.instance.dio.httpClientAdapter = _OfflineAdapter();

    final auth = _stockManager();
    final router = AppRoutes.createRouter(auth);
    addTearDown(router.dispose);

    final inventory = InventoryViewmodel.seeded(
      products: [
        product(
          id: 6,
          variants: [
            variant(id: 8, productId: 6, threshold: 20, maxStockLevel: 50),
          ],
        ),
      ],
      batches: [batch(id: 8, variantId: 8, qty: 3)],
      alerts: [alert(id: 41, variantId: 8)],
      // The fakes carry the SAME rows: the Stock Manager's landing dashboard calls
      // `load()` on the way through the router, so an empty catalogue fake would
      // wipe the seeding this test depends on.
      catalogue: FakeProductsRepository(
        products: [
          product(
            id: 6,
            variants: [
              variant(id: 8, productId: 6, threshold: 20, maxStockLevel: 50),
            ],
          ),
        ],
        batches: [batch(id: 8, variantId: 8, qty: 3)],
      ),
      inventory: FakeInventoryRepository(alerts: [alert(id: 41, variantId: 8)]),
      catalogueLists: FakeCatalogueRepository(),
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          // Exactly the set `main.dart` installs that this route needs.
          ChangeNotifierProvider<AuthViewmodel>.value(value: auth),
          ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
          ChangeNotifierProvider<SuppliersPurchasesViewmodel>(
            create: (_) => SuppliersPurchasesViewmodel(
              repository: _StubSupplierRepository(),
            ),
          ),
          ChangeNotifierProvider<ProductTrackingViewmodel>(
            create: (_) => ProductTrackingViewmodel(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go(AppRoutes.inventoryLowStock);
    await tester.pumpAndSettle();

    expect(
      find.byType(InventoryLowStockPage),
      findsOneWidget,
      reason: 'the Low stock route must resolve through the real router',
    );

    // And the collaborator it needs is reachable from a DIALOG: Reorder builds the
    // New purchase order form, which lives outside the page's provider scope.
    await tester.tap(find.text('Reorder'));
    await tester.pumpAndSettle();

    expect(find.byType(PurchasesFormDialog), findsOneWidget);
  });
}
