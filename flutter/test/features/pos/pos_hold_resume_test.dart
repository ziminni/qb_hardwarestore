// Phase 3's two missing links: the till had no way to PARK a basket, and the
// held-transactions tab's Resume button only walked the cashier back to the till
// with an empty cart — a parked basket the cashier cannot pick back up is a
// customer's items stranded on the server.
//
// What a viewmodel test cannot see is what is pinned here: that the Hold button
// exists at the counter, posts the cart's OWN lines (VariantUOM ids, quantities
// and the quoted prices), clears the till only on success, and that Resume both
// navigates AND hands the basket over.

import 'package:client/data/models/held_cart.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/held_cart_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/held_cart_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_held_transactions_page.dart';
import 'package:client/features/pos/views/pos_transaction_page.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class _StubHeldCarts extends HeldCartService {
  final List<({int? customerId, String notes, List<HeldCartItem> items})> holds =
      [];
  Object? failHold;
  List<HeldCart> carts = const [];

  @override
  Future<List<HeldCart>> fetchAll() async => carts;

  @override
  Future<HeldCart> hold({
    int? customerId,
    String notes = '',
    required List<HeldCartItem> items,
  }) async {
    holds.add((customerId: customerId, notes: notes, items: items));
    if (failHold != null) throw failHold!;
    return HeldCart(
      id: 42,
      customerId: customerId,
      customerName: null,
      cashierName: 'Ana Cruz',
      notes: notes,
      items: items,
      createdAt: DateTime(2026, 10, 21, 10),
    );
  }
}

/// The till is gated on an open shift, so a hold test needs one or the cart is
/// never built and the button does not exist.
class _OpenShift extends ShiftService {
  @override
  Future<Shift?> fetchCurrent() async => Shift(
    id: 1,
    cashierName: 'Ana Cruz',
    status: Shift.openStatus,
    openingFloat: 5000,
    closingCount: null,
    openedAt: DateTime(2026, 10, 21, 8),
    closedAt: null,
    notes: '',
    zReading: null,
  );
}

// The till loads the live catalogue on open. These fail deterministically so no
// test touches the network and the bundled rows stay the catalogue under test.
class _FailingProductsRepository extends ProductsRepository {
  _FailingProductsRepository() : super(ProductsService());

  @override
  Future<ProductsSnapshot> loadCatalogue() async =>
      throw const ProductsServiceException('Cannot connect.');
}

class _FailingInventoryRepository extends InventoryRepository {
  _FailingInventoryRepository() : super(InventoryService());

  @override
  Future<List<SystemAlert>> loadAlerts() async =>
      throw const InventoryServiceException('Cannot connect.');

  @override
  Future<List<StockAdjustment>> loadAdjustments() async => [];
}

/// A [GoRouter] holding the two POS screens a resume crosses, so the navigation
/// half of Resume is observable rather than assumed.
Future<void> pumpHeldPage(WidgetTester tester, HeldCartViewmodel vm) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final router = GoRouter(
    initialLocation: AppRoutes.posHeld,
    routes: [
      GoRoute(
        path: AppRoutes.posHeld,
        builder: (_, _) => PosHeldTransactionsPage(viewmodel: vm),
      ),
      GoRoute(
        path: AppRoutes.posDashboard,
        builder: (_, _) => const Scaffold(body: Text('the till')),
      ),
    ],
  );
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  late InventoryViewmodel inventory;
  late PosTransactionViewmodel cart;
  late _StubHeldCarts heldService;
  late HeldCartViewmodel heldCarts;

  setUp(() {
    inventory = InventoryViewmodel(
      products: _FailingProductsRepository(),
      inventory: _FailingInventoryRepository(),
    );
    cart = PosTransactionViewmodel(inventory, ProductTrackingViewmodel());
    heldService = _StubHeldCarts();
    heldCarts = HeldCartViewmodel(service: heldService);
  });

  Future<void> pumpTill(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>.value(
        value: AuthViewmodel(AuthRepository(AuthService())),
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
            ChangeNotifierProvider<ProductTrackingViewmodel>.value(
              value: ProductTrackingViewmodel(),
            ),
          ],
          child: MaterialApp(
            home: PosTransactionPage(
              viewmodel: cart,
              shiftViewmodel: ShiftViewmodel(service: _OpenShift()),
              heldCartViewmodel: heldCarts,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  void addOneLine() {
    expect(cart.addLine(cart.filteredProducts.first, 2), isNull);
  }

  group('the till can HOLD a basket', () {
    testWidgets('the button is live with items and posts the cart itself', (
      tester,
    ) async {
      addOneLine();
      final line = cart.lines.single;
      await pumpTill(tester);

      final hold = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Hold transaction'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(hold.onPressed, isNotNull, reason: 'a full cart can be parked');

      await tester.tap(find.text('Hold transaction'));
      await tester.pumpAndSettle();

      expect(heldService.holds, hasLength(1));
      final posted = heldService.holds.single;
      expect(posted.customerId, isNull, reason: 'an anonymous sale is parked');
      expect(posted.items, hasLength(1));
      // The VariantUOM id, not a ProductVariant id: the hold payload has the same
      // unit contract as checkout (decision 06 section 2).
      expect(posted.items.single.variantUom, line.variantUomId);
      expect(posted.items.single.qty, line.quantity);
      expect(posted.items.single.unitPrice, line.unitPrice);

      expect(find.text('Cart held'), findsOneWidget);
      expect(
        cart.lines,
        isEmpty,
        reason: 'the basket now lives on the server, so the till must free up',
      );
      expect(heldCarts.carts.single.id, 42);
    });

    testWidgets('an EMPTY cart cannot be held', (tester) async {
      await pumpTill(tester);

      final hold = tester.widget<OutlinedButton>(
        find.ancestor(
          of: find.text('Hold transaction'),
          matching: find.byType(OutlinedButton),
        ),
      );
      expect(
        hold.onPressed,
        isNull,
        reason: 'parking an empty basket leaves a row that resumes to nothing',
      );
      expect(heldService.holds, isEmpty);
    });

    testWidgets('a failed hold KEEPS the cart and says why', (tester) async {
      addOneLine();
      heldService.failHold = const HeldCartServiceException(
        'Cannot connect to the BuildPro server.',
      );
      await pumpTill(tester);

      await tester.tap(find.text('Hold transaction'));
      await tester.pumpAndSettle();

      expect(find.text('Cannot connect to the BuildPro server.'), findsOneWidget);
      expect(
        cart.lines,
        hasLength(1),
        reason:
            'the basket was not parked, so clearing the till would lose the sale',
      );
    });
  });

  group('the till LOADS a resumed basket', () {
    testWidgets('pending resume fills the cart once, on open', (tester) async {
      final source = cart.filteredProducts.first;
      final option = cart.saleOptionsFor(source).first;
      heldCarts.resumeCart(
        HeldCart(
          id: 7,
          customerId: null,
          customerName: null,
          cashierName: 'Ana Cruz',
          notes: 'pay tomorrow',
          items: [
            HeldCartItem(
              id: 70,
              variantUom: option.variantUomId,
              qty: 2,
              unitPrice: 123.45,
            ),
          ],
          createdAt: DateTime(2026, 10, 21, 9),
        ),
      );

      await pumpTill(tester);

      expect(cart.lines, hasLength(1));
      expect(cart.lines.single.variantUomId, option.variantUomId);
      expect(cart.lines.single.quantity, 2);
      expect(
        cart.lines.single.unitPrice,
        123.45,
        reason: 'the customer was quoted this price when the basket was parked',
      );
      expect(
        heldCarts.pendingResume,
        isNull,
        reason: 'a hand-off is consumed, or reopening the till re-loads it',
      );
    });
  });

  group('PosTransactionViewmodel.loadHeldCart', () {
    HeldCart heldWith(List<HeldCartItem> items, {String? customerName}) =>
        HeldCart(
          id: 3,
          customerId: customerName == null ? null : 11,
          customerName: customerName,
          cashierName: 'Ana Cruz',
          notes: '',
          items: items,
          createdAt: DateTime(2026, 10, 21, 9),
        );

    test('keeps the QUOTED price, not a re-read catalogue price', () {
      final option = cart.saleOptionsFor(cart.filteredProducts.first).first;
      final restored = cart.loadHeldCart(
        heldWith([
          HeldCartItem(
            id: 1,
            variantUom: option.variantUomId,
            qty: 4,
            unitPrice: 1.25,
          ),
        ]),
      );

      expect(restored, 1);
      expect(cart.lines.single.unitPrice, 1.25);
      expect(cart.lines.single.quantity, 4);
      expect(
        cart.lines.single.productName,
        option.productName,
        reason: 'a held line carries ids only; names come from the catalogue',
      );
    });

    test('a line the catalogue no longer sells is KEPT, so validate names it', () {
      cart.loadHeldCart(
        heldWith([
          const HeldCartItem(id: 1, variantUom: 999999, qty: 1, unitPrice: 5),
        ]),
      );

      expect(
        cart.lines,
        hasLength(1),
        reason: 'dropping it would silently shorten the customer\u2019s order',
      );
      expect(cart.validate(), contains('no longer available'));
    });

    test('REPLACES the cart, and keeps the basket account', () {
      expect(cart.addLine(cart.filteredProducts.first, 1), isNull);
      final option = cart.saleOptionsFor(cart.filteredProducts.first).first;

      cart.loadHeldCart(
        heldWith([
          HeldCartItem(
            id: 1,
            variantUom: option.variantUomId,
            qty: 2,
            unitPrice: 9,
          ),
        ], customerName: 'Maria Santos'),
      );

      expect(cart.lines, hasLength(1), reason: 'resume means "this basket"');
      expect(cart.customerLabel, 'Maria Santos');
      expect(cart.selectedCustomer?.id, 11);
    });
  });

  group('the held-transactions tab RESUMES into the till', () {
    testWidgets('Resume navigates AND hands the basket over', (tester) async {
      heldService.carts = [
        HeldCart(
          id: 1,
          customerId: 11,
          customerName: 'Dela Cruz Construction',
          cashierName: 'Ana Cruz',
          notes: '',
          items: const [
            HeldCartItem(id: 10, variantUom: 5, qty: 3, unitPrice: 99.5),
          ],
          createdAt: DateTime(2026, 10, 21, 9),
        ),
      ];
      await pumpHeldPage(tester, heldCarts);

      await tester.tap(find.text('Resume'));
      await tester.pumpAndSettle();

      expect(
        find.text('the till'),
        findsOneWidget,
        reason: 'Resume returns the cashier to the till, per decision 03',
      );
      expect(heldCarts.pendingResume?.id, 1);
      expect(heldCarts.pendingResume?.items.single.qty, 3);
    });
  });
}
