// Stocker-workflow phases 1-3 render checks.
//
// Three screens had to behave differently on purpose:
//  - Returns reads the live RETURN transactions through `InventorySalesViewmodel`
//    (the `inventory` role has GET on /api/v1/transactions/ via IsPOSOrReadOnly);
//  - Reports (card K10, decision D4) stopped being a lock screen and now shows
//    the stock numbers this role can already load, through the same
//    `InventoryViewmodel` the stock screens use. Every /api/v1/reports/* endpoint
//    is still IsManagerRole-gated, so the page says that in one footnote and
//    calls no reports endpoint;
//  - Settings is a read-only "Store information" card with NO Save button,
//    because the stocker cannot change store settings and the shared form's Save
//    button is a no-op even for admins.
//
// Each test asserts the absence that matters as well as the presence: a lock
// icon on Reports or a "Save settings" button on Settings would mean the screen
// promises something the role cannot do.

import 'package:client/core/format/format.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_reports_page.dart';
import 'package:client/features/inventory/views/inventory_returns_page.dart';
import 'package:client/features/inventory/views/inventory_settings_page.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

class _StubSalesService extends SalesService {
  _StubSalesService({this.rows = const [], this.failure});

  final List<TransactionRecord> rows;
  final String? failure;

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async {
    final failure = this.failure;
    if (failure != null) throw SalesServiceException(failure);
    return rows;
  }
}

TransactionRecord _returnRow() => TransactionRecord(
  id: 10,
  transactionNo: 'TRX-20261019-0002',
  transDate: DateTime(2026, 10, 19, 9),
  customerId: 3,
  customerName: 'Dela Cruz Construction',
  cashierName: 'Cashy Ir',
  source: 'RETURN',
  originalTransactionId: 9,
  status: 'COMPLETED',
  grandTotal: -50,
  items: const [
    TransactionLineItem(
      variantUomId: 1,
      variantUomCode: 'BAG',
      qty: -1,
      unitPrice: 50,
      subtotal: -50,
    ),
  ],
  payments: const [TransactionPayment(method: 'CASH', amountTendered: -50)],
);

Future<void> _pump(
  WidgetTester tester,
  Widget page, {
  SalesService? sales,
  InventoryViewmodel? inventory,
}) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewmodel>(
          create: (_) => AuthViewmodel(AuthRepository(AuthService())),
        ),
        ChangeNotifierProvider<InventorySalesViewmodel>(
          create: (_) =>
              InventorySalesViewmodel(service: sales ?? _StubSalesService()),
        ),
        ChangeNotifierProvider<InventoryViewmodel>(
          create: (_) => inventory ?? InventoryViewmodel(),
        ),
      ],
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('Returns', () {
    testWidgets('lists the live RETURN transactions', (tester) async {
      await _pump(
        tester,
        const InventoryReturnsPage(),
        sales: _StubSalesService(rows: [_returnRow()]),
      );

      expect(find.text('Returns & Refunds'), findsOneWidget);
      expect(find.text('TRX-20261019-0002'), findsOneWidget);
      expect(find.text('No returns recorded.'), findsNothing);
    });

    testWidgets('an empty result says so instead of showing a blank table', (
      tester,
    ) async {
      await _pump(tester, const InventoryReturnsPage());
      expect(find.text('No returns recorded.'), findsOneWidget);
    });

    testWidgets('a failed load shows the error with a retry', (tester) async {
      await _pump(
        tester,
        const InventoryReturnsPage(),
        sales: _StubSalesService(
          failure: 'Cannot connect to the BuildPro server.',
        ),
      );

      expect(find.textContaining('Cannot connect'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    });
  });

  group('Reports', () {
    // Decision D4: the lock screen is gone. The page shows the stock value and
    // the low/out counts this role can already read, derived from the same
    // `InventoryViewmodel` the stock screens use, so no number here is invented
    // and no manager endpoint is called.
    testWidgets('shows stock value and low/out counts from the inventory data', (
      tester,
    ) async {
      await _pump(
        tester,
        const InventoryReportsPage(),
        inventory: await _reportsStore(),
      );

      expect(find.byIcon(Icons.lock_outline), findsNothing);
      expect(find.text('Reports'), findsWidgets);
      // 10 x 250 + 2 x 250; the out-of-stock variant has no batch, so no cost.
      expect(_tile(tester, 'INVENTORY VALUE').value, formatPeso(3000));
      expect(_tile(tester, 'LOW STOCK').value, '1');
      expect(_tile(tester, 'OUT OF STOCK').value, '1');
      // The manager reports really are still manager-only, so one footnote says
      // so. It is a sentence on a page with numbers now, not a whole screen.
      expect(
        find.textContaining('available to Store Managers and above'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('a failed load shows the error and a retry, not zero tiles', (
      tester,
    ) async {
      await _pump(
        tester,
        const InventoryReportsPage(),
        inventory: await _reportsStore(failing: true),
      );

      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(
        find.text('Cannot connect to the BuildPro server.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      expect(find.byType(EmptyState), findsNothing);
      // A failed read must not paint ₱0.00 as if the store held nothing.
      expect(find.byType(MetricTile), findsNothing);
    });

    testWidgets('an empty catalogue says so instead of showing zeroes', (
      tester,
    ) async {
      await _pump(
        tester,
        const InventoryReportsPage(),
        inventory: await _reportsStore(empty: true),
      );

      expect(find.byType(EmptyState), findsOneWidget);
      expect(find.text('No stock records yet.'), findsOneWidget);
      expect(find.byType(MetricTile), findsNothing);
    });
  });

  group('Settings', () {
    // Card K10: the three store facts are a read-only "Store information" card,
    // the same look as the admin Settings screen (card A6). Disabled fields
    // looked like a form waiting to be enabled, and there is no settings
    // endpoint to enable them.
    testWidgets('shows the store details read-only, with no Save button', (
      tester,
    ) async {
      await _pump(tester, const InventorySettingsPage());

      expect(find.text('Store information'), findsOneWidget);
      // D-03 moved these off `AdminMockData` and onto the constants both
      // Settings screens share, so the expected literals moved with them.
      expect(find.text('QB Hardware & Construction Supplies'), findsOneWidget);
      expect(find.text('contact@qbhardware.com'), findsOneWidget);
      expect(find.text('+63 912 345 6789'), findsOneWidget);
      expect(
        find.byType(TextFormField),
        findsNothing,
        reason: 'no field may imply these values can be edited',
      );
      expect(find.text('Save settings'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
    });
  });
}

/// The tile carrying [label], so a count is read from the tile that names it.
MetricTile _tile(WidgetTester tester, String label) => tester
    .widgetList<MetricTile>(find.byType(MetricTile))
    .firstWhere((tile) => tile.label == label);

/// Three variants: 10 on hand at ₱250 landed, 2 low against a threshold of 5,
/// and one with no batch (out of stock). Value: 10 x 250 + 2 x 250 = ₱3,000.
Future<InventoryViewmodel> _reportsStore({
  bool failing = false,
  bool empty = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final products = empty
      ? const <Product>[]
      : [
          product(
            id: 1,
            name: 'Circuit Breaker 20A 1-pole',
            variants: [variant(id: 1, productId: 1, threshold: 5)],
          ),
          product(
            id: 2,
            name: 'Deformed Steel Bar 10 mm x 6 m Grade 60',
            variants: [variant(id: 2, productId: 2, threshold: 5)],
          ),
          product(
            id: 3,
            name: 'Fill Sand',
            variants: [variant(id: 3, productId: 3, threshold: 5)],
          ),
        ];
  final batches = empty
      ? const <InventoryBatch>[]
      : [
          batch(id: 1, variantId: 1, qty: 10, cost: 250),
          batch(id: 2, variantId: 2, qty: 2, cost: 250),
        ];
  final store = InventoryViewmodel(
    products: failing
        ? _FailingProductsRepository()
        : FakeProductsRepository(products: products, batches: batches),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );
  await store.load();
  return store;
}

/// Answers the catalogue read with the transport failure the live app shows when
/// the BuildPro server is unreachable.
class _FailingProductsRepository extends ProductsRepository {
  _FailingProductsRepository() : super(ProductsService());

  @override
  Future<ProductsSnapshot> loadCatalogue() async =>
      throw const ProductsServiceException(
        'Cannot connect to the BuildPro server.',
      );
}
