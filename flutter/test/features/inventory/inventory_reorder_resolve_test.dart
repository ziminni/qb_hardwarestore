// Phase 4 Task 4 — the two low-stock controls that used to lie.
//
//   Reorder  opened "Future Purchasing connection — will connect to the
//            Purchasing module in a future implementation." It now opens the real
//            New purchase order dialog, prefilled with the variant and a suggested
//            quantity.
//   Resolve  did not exist, so a cleared alert stayed open for ever. It now calls
//            POST /alerts/{id}/resolve/ and shows who cleared it and when — and
//            only the roles the server admits (IsInventoryRole) see the button.

import 'package:client/data/models/purchase_draft.dart';
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
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/suppliers/widgets/purchases_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

class _StubSupplierRepository extends SupplierRepository {
  _StubSupplierRepository() : super(service: SupplierService());

  final List<Map<String, dynamic>> createdOrders = [];
  final List<int> placedOrders = [];
  String? failure;

  @override
  Future<List<Supplier>> fetchSuppliers() async => const [
    Supplier(
      id: 3,
      companyName: 'Cebu Steel Works',
      contactPerson: 'Dan Uy',
      phone: '',
      email: '',
      address: '',
    ),
  ];

  @override
  Future<List<PurchaseOrder>> fetchPurchaseOrders() async => const [];

  @override
  Future<int> createPurchaseOrder(PurchaseOrderDraft draft) async {
    final error = failure;
    if (error != null) throw SupplierServiceException(error);
    createdOrders.add(draft.toJson());
    return 55;
  }

  /// "Place order" is a SECOND call (`place/`), so the stub must answer it too —
  /// otherwise the test would reach a real ApiClient that was never initialised.
  @override
  Future<void> placePurchaseOrder(int id) async {
    final error = failure;
    if (error != null) throw SupplierServiceException(error);
    placedOrders.add(id);
  }
}

AuthViewmodel _auth({String? role}) {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  if (role != null) {
    auth.user = User(
      id: 1,
      username: 'stock',
      email: 'stock@qb.ph',
      fullName: 'Ana Lopez',
      role: Role(id: 4, name: role, displayName: role),
    );
  }
  return auth;
}

void main() {
  late FakeInventoryRepository alerts;
  late InventoryViewmodel inventory;
  late _StubSupplierRepository suppliers;

  setUp(() {
    alerts = FakeInventoryRepository(alerts: [alert(id: 41, variantId: 8)]);
    inventory = InventoryViewmodel(
      products: FakeProductsRepository(
        products: [
          product(
            id: 6,
            variants: [
              // 3 on hand, threshold 20, ceiling 50 → suggested 47.
              variant(
                id: 8,
                productId: 6,
                name: '20A 1-pole',
                threshold: 20,
                maxStockLevel: 50,
              ),
            ],
          ),
        ],
        // cost 235 = the newest batch's landed cost, which the dialog prefills as
        // the unit cost (decision 08 — the DISPLAYED cost, not a charging price).
        batches: [batch(id: 8, variantId: 8, qty: 3, cost: 235)],
      ),
      inventory: alerts,
      catalogue: FakeCatalogueRepository(),
    );
    suppliers = _StubSupplierRepository();
  });

  Future<void> pump(WidgetTester tester, {String? role}) async {
    await inventory.load();
    tester.view.physicalSize = const Size(3600, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>.value(value: _auth(role: role)),
          ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
          ChangeNotifierProvider<SuppliersPurchasesViewmodel>(
            create: (_) => SuppliersPurchasesViewmodel(repository: suppliers),
          ),
        ],
        child: const MaterialApp(home: InventoryLowStockPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Reorder opens the REAL purchase-order dialog, prefilled', (
    tester,
  ) async {
    await pump(tester, role: 'Stock Manager');

    await tester.tap(find.text('Reorder'));
    await tester.pumpAndSettle();

    expect(find.byType(PurchasesFormDialog), findsOneWidget);
    // Prefilled from `suggestedReorderQty`: max_stock_level (50) − on hand (3),
    // read off the quantity field itself rather than any text that happens to
    // show the same number.
    final qty = tester.widget<TextFormField>(
      find.byKey(const ValueKey('po-qty-8')),
    );
    expect(qty.controller?.text, '47');
    expect(find.text('Circuit Breaker'), findsWidgets);
    // The placeholder dialog is gone for good.
    expect(find.text('Future Purchasing connection'), findsNothing);
  });

  testWidgets('placing the prefilled order POSTs it with that one line', (
    tester,
  ) async {
    await pump(tester, role: 'Stock Manager');

    await tester.tap(find.text('Reorder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Place order'));
    await tester.pumpAndSettle();

    expect(suppliers.createdOrders.single['supplier'], 3);
    expect(suppliers.placedOrders, [55]);
    expect(suppliers.createdOrders.single['items'], [
      {'variant': 8, 'ordered_qty': 47.0, 'unit_cost': 235.0},
    ]);
  });

  testWidgets('Resolve calls the server and the trail is shown', (
    tester,
  ) async {
    await pump(tester, role: 'Stock Manager');

    await tester.tap(find.text('Resolve'));
    await tester.pumpAndSettle();

    expect(alerts.resolvedAlertIds, [41]);

    // The row leaves the open list; the resolved tab shows who and when — both
    // read from the server's answer, not from a local guess.
    await tester.tap(find.text('Show resolved'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Resolved by Ana Lopez'), findsOneWidget);
    expect(find.textContaining('2026-10-25 14:30'), findsOneWidget);
    // A resolved alert is not offered for resolving again.
    expect(find.text('Resolve'), findsNothing);
  });

  testWidgets('a cashier does not see Resolve at all', (tester) async {
    await pump(tester, role: 'Cashier');

    // The server refuses `resolve/` for this role (`IsInventoryRole`), so the
    // button is not rendered rather than rendered-and-refused.
    expect(find.text('Resolve'), findsNothing);
    expect(find.text('Reorder'), findsOneWidget);
  });

  testWidgets('a refused resolve shows the server message, not a success', (
    tester,
  ) async {
    await pump(tester, role: 'Stock Manager');
    alerts.resolveError = 'Alert 41 was already resolved.';

    await tester.tap(find.text('Resolve'));
    await tester.pumpAndSettle();

    expect(find.text('Alert 41 was already resolved.'), findsOneWidget);
  });
}
