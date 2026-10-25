// F2: the three stock screens must not claim a fact nobody checked.
//
// `InventoryLowStockPage`, `InventoryStockPage` and
// `InventoryStockMovementsPage` read `InventoryViewmodel` but never triggered a
// load and had no loading or error state. Since the store stopped self-seeding,
// a web refresh on `/inventory/low-stock` painted "No low-stock products match
// this search." before anything had been fetched — and kept painting it forever,
// because nothing ever fetched. A failed load looked exactly the same.
//
// The contract these tests pin, per page:
//   * not loaded yet  -> a spinner, never the empty message
//   * load failed     -> the error banner with a Retry, never the empty message
//   * loaded, empty   -> the empty message (the only state allowed to say it)
//
// The third case also proves the page loads itself on open: an unloaded store
// would sit on the spinner and never reach the empty state.

import 'dart:async';

import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_low_stock_page.dart';
import 'package:client/features/inventory/views/inventory_stock_movements_page.dart';
import 'package:client/features/inventory/views/inventory_stock_page.dart';
import '../../support/phase4_fakes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Answers the catalogue the test wrote down — or fails, or never finishes.
class _ScriptedProductsRepository extends ProductsRepository {
  _ScriptedProductsRepository({this.failure, this.gate})
    : snapshot = null,
      super(ProductsService());

  Object? failure;
  Future<void>? gate;
  ProductsSnapshot? snapshot;
  int calls = 0;

  @override
  Future<ProductsSnapshot> loadCatalogue() async {
    calls++;
    final pending = gate;
    if (pending != null) await pending;
    final error = failure;
    if (error != null) throw error;
    return snapshot ?? ProductsSnapshot(products: const [], batches: const []);
  }
}

ProductsSnapshot _oneProduct() => ProductsSnapshot(
  products: seededProducts(),
  batches: [batch(id: 1, variantId: 1, qty: 130)],
);

InventoryViewmodel _store(
  _ScriptedProductsRepository products, {
  FakeInventoryRepository? inventory,
}) => InventoryViewmodel(
  products: products,
  inventory: inventory ?? FakeInventoryRepository(),
  catalogue: FakeCatalogueRepository(),
);

const _lowStockEmpty = 'No low-stock products match this search.';
const _stockEmpty = 'No stock records match these filters.';
const _movementsEmpty = 'No stock movements match your filters.';

/// One page under test: how to seed the row it renders, and the empty copy only
/// a COMPLETED load may show.
class _Subject {
  const _Subject({
    required this.name,
    required this.page,
    required this.emptyMessage,
    this.rows = const [],
  });

  final String name;
  final Widget page;
  final String emptyMessage;

  /// The inventory rows that make this page show a product row (alerts for the
  /// low-stock screen, adjustments for the movements screen, nothing for the
  /// stock screen, which reads the catalogue).
  final List<StockAdjustment> rows;

  /// The alerts the low-stock screen renders from — membership comes from the
  /// server, so a low-stock row needs one (decision 13).
  List<SystemAlert> get alerts =>
      name == 'Low stock' ? [alert(variantId: 1)] : const <SystemAlert>[];
}

StockAdjustment _adjustment() => StockAdjustment(
  id: 1,
  variantId: 1,
  userId: 1,
  adjustmentType: StockAdjustmentType.damage,
  quantityAdjusted: -2,
  remarks: 'Cracked casing.',
  // Inside the movements page's default "this month" range.
  timestamp: DateTime.now().subtract(const Duration(hours: 1)),
);

void main() {
  Future<void> pumpPage(
    WidgetTester tester,
    InventoryViewmodel store,
    Widget page,
  ) async {
    // The shared shell reads AuthViewmodel and its skeleton needs a desktop
    // window — same harness notes as the other inventory page tests.
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
        child: MaterialApp(home: page),
      ),
    );
  }

  final pages = [
    _Subject(
      name: 'Low stock',
      page: const InventoryLowStockPage(),
      emptyMessage: _lowStockEmpty,
    ),
    _Subject(
      name: 'Stock',
      page: const InventoryStockPage(),
      emptyMessage: _stockEmpty,
    ),
    _Subject(
      name: 'Stock movements',
      page: const InventoryStockMovementsPage(),
      emptyMessage: _movementsEmpty,
      rows: [_adjustment()],
    ),
  ];

  for (final subject in pages) {
    group(subject.name, () {
      testWidgets(
        'shows a spinner, not the empty message, while the first load runs',
        (tester) async {
          final gate = Completer<void>();
          final products = _ScriptedProductsRepository(gate: gate.future);
          final store = _store(products);

          await pumpPage(tester, store, subject.page);
          // Two frames: the first builds, the second runs the post-frame load.
          await tester.pump();
          await tester.pump();

          expect(products.calls, 1, reason: 'the page loads on open');
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.text(subject.emptyMessage), findsNothing);

          gate.complete();
          await tester.pumpAndSettle();
        },
      );

      testWidgets(
        'a failed load shows the banner and a Retry, not the empty message',
        (tester) async {
          final products = _ScriptedProductsRepository(
            failure: const ProductsServiceException(
              'Cannot connect to the BuildPro server.',
            ),
          );
          final store = _store(products);

          await pumpPage(tester, store, subject.page);
          await tester.pumpAndSettle();

          expect(
            find.text('Cannot connect to the BuildPro server.'),
            findsOneWidget,
          );
          expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
          expect(
            find.text(subject.emptyMessage),
            findsNothing,
            reason: 'a failure is not an empty result',
          );
        },
      );

      testWidgets('Retry re-runs the load and the rows appear', (tester) async {
        final products = _ScriptedProductsRepository(
          failure: const ProductsServiceException('Cannot connect.'),
        );
        final store = _store(
          products,
          inventory: FakeInventoryRepository(
            alerts: subject.alerts,
            adjustments: subject.rows,
          ),
        );

        await pumpPage(tester, store, subject.page);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

        products.failure = null;
        products.snapshot = _oneProduct();
        await tester.tap(find.widgetWithText(TextButton, 'Retry'));
        await tester.pumpAndSettle();

        expect(products.calls, 2);
        expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
        expect(find.text(subject.emptyMessage), findsNothing);
        expect(find.textContaining('Portland Cement'), findsWidgets);
      });

      testWidgets('a successful but empty load shows the empty message', (
        tester,
      ) async {
        // An unloaded store plus an empty catalogue: only the load-on-open path
        // can get here, so this also proves the page fetches for itself.
        final products = _ScriptedProductsRepository();
        final store = _store(products);

        await pumpPage(tester, store, subject.page);
        await tester.pumpAndSettle();

        expect(products.calls, 1);
        expect(find.text(subject.emptyMessage), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
      });
    });
  }
}
