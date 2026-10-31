// Decision D-03 (sales-manager-workflow): both admin monitoring pages rendered
// `AdminMockData`: a fake weekly chart and four fake inventory tiles, sitting
// in the admin shell next to screens that show real money. A manager reading
// "P1 240 000 gross" off invented bars is worse than reading nothing.
//
// Card A3 adds the two things those pages could not do: a list of what is low or
// out of stock (the data was loaded, no screen showed it), and period chips over
// the sales summary the page already read (the range was fixed at seven days).
// These tests pin:
//   * the low/out list leads with out-of-stock rows, badges its status and groups
//     its quantities (`formatQuantity`),
//   * the tiles count what the loaded stock says,
//   * the highest-value panel ranks by value at landed cost,
//   * one failed first load is ONE banner, never a banner plus an empty list,
//   * the sales period chips filter the daily rows already loaded (one read),
//     and the page says out loud that they do,
//   * a search narrows the days on screen,
//   * the chart receives the days the server returned, in `formatDate` (D6),
//   * an empty range says "no data" instead of crashing in `AdminSalesChart`,
//     whose `values.reduce` throws on an empty list,
//   * an all-zero and a negative week still paint (the clamps added in b5cfc33).

import 'package:client/core/format/format.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/features/admin/views/inventory_monitoring_page.dart';
import 'package:client/features/admin/views/sales_monitoring_page.dart';
import 'package:client/features/admin/widgets/admin_sales_chart.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

class _StubReportsRepository extends ReportsRepository {
  _StubReportsRepository() : super();

  int salesCalls = 0;
  int valuationCalls = 0;
  String? lastFrom;
  String? lastTo;
  String? failure;

  SalesSummary summary = const SalesSummary(
    from: '2026-10-14',
    to: '2026-10-20',
    totalTransactions: 3,
    totalGross: 3500,
    totalVat: 0,
    totalDiscounts: 0,
    days: [
      SalesDay(
        day: '2026-10-19',
        transactions: 2,
        gross: 1000,
        vat: 0,
        discounts: 0,
      ),
      SalesDay(
        day: '2026-10-20',
        transactions: 3,
        gross: 2500,
        vat: 0,
        discounts: 0,
      ),
    ],
  );

  InventoryValuation valuation = const InventoryValuation(
    batchCount: 12,
    totalUnits: 1200,
    totalCost: 5000,
    totalRetail: 8000,
    categories: [],
  );

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
    salesCalls++;
    lastFrom = from;
    lastTo = to;
    final failure = this.failure;
    if (failure != null) throw ReportsServiceException(failure);
    return summary;
  }

  @override
  Future<InventoryValuation> fetchInventoryValuation() async {
    valuationCalls++;
    final failure = this.failure;
    if (failure != null) throw ReportsServiceException(failure);
    return valuation;
  }
}

/// Answers a catalogue read with the transport failure the live app shows when
/// the BuildPro server is unreachable, until a test turns [failing] off.
class _FailingProductsRepository extends FakeProductsRepository {
  /// Whether the next read still fails. A test flips this to prove the retry
  /// re-reads and recovers, instead of pinning a page that can never recover.
  bool failing = true;

  /// Every read attempt, failed or not: what proves the retry reached the store.
  int attempts = 0;

  @override
  Future<ProductsSnapshot> loadCatalogue() async {
    attempts++;
    if (failing) {
      throw const ProductsServiceException(
        'Cannot connect to the BuildPro server.',
      );
    }
    return super.loadCatalogue();
  }
}

const Key _lowOutPanel = Key('admin-monitoring-low-out');
const Key _valuePanel = Key('admin-monitoring-value');
const Key _salesEmpty = Key('sales-monitoring-empty');

Widget _app(Widget child, {InventoryViewmodel? inventory}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthViewmodel>.value(
        value: AuthViewmodel(AuthRepository(AuthService())),
      ),
      ChangeNotifierProvider<InventoryViewmodel>.value(
        value: inventory ?? _stock(),
      ),
    ],
    child: MaterialApp(home: child),
  );
}

/// A stock book with one out-of-stock variant, one low variant and one healthy
/// one, plus a long product name so a row cannot shorten what matters.
InventoryViewmodel _stock() {
  SharedPreferences.setMockInitialValues({});
  return InventoryViewmodel.seeded(
    products: _products(),
    batches: _batches(),
    catalogue: FakeProductsRepository(
      products: _products(),
      batches: _batches(),
    ),
    inventory: FakeInventoryRepository(),
    catalogueLists: FakeCatalogueRepository(),
  );
}

/// The same book, but NOT loaded yet: how a real visit starts, because
/// production builds the store empty and the page triggers the first read.
InventoryViewmodel _unloadedStock() {
  SharedPreferences.setMockInitialValues({});
  return InventoryViewmodel(
    products: FakeProductsRepository(
      products: _products(),
      batches: _batches(),
    ),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );
}

List<Product> _products() {
  return <Product>[
    product(
      id: 1,
      name: 'Marine Plywood 3/4 in x 4 ft x 8 ft',
      variants: [variant(id: 1, productId: 1, name: '3/4 in', threshold: 20)],
    ),
    product(
      id: 2,
      name: 'Portland Cement',
      variants: [
        variant(id: 2, productId: 2, name: '40 kg bag', threshold: 30),
      ],
    ),
    product(
      id: 3,
      name: 'Fill Sand',
      variants: [variant(id: 3, productId: 3, name: 'Screened', threshold: 5)],
    ),
  ];
}

List<InventoryBatch> _batches() {
  return <InventoryBatch>[
    // Nothing left: the row an owner acts on first.
    batch(id: 1, variantId: 1, qty: 0, cost: 640),
    // 12 of 30: low, and the highest value at landed cost (2,160).
    batch(id: 2, variantId: 2, qty: 12, cost: 180),
    // Healthy: 900 at 2.00 is 1,800 at cost.
    batch(id: 3, variantId: 3, qty: 900, cost: 2),
  ];
}

Finder _tileValue(String label, String value) => find.descendant(
  of: find.widgetWithText(MetricTile, label),
  matching: find.text(value),
);

void _sizeUp(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

String _stamp(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// A month of trading, built off today so the period chips have something to
/// narrow whatever day the suite runs on: 1,000 today, 500 yesterday, 4,000 ten
/// days ago.
_StubReportsRepository _monthOfSales() {
  final today = DateTime.now();
  SalesDay day(int back, {required int transactions, required double gross}) =>
      SalesDay(
        day: _stamp(today.subtract(Duration(days: back))),
        transactions: transactions,
        gross: gross,
        vat: 0,
        discounts: 0,
      );
  return _StubReportsRepository()
    ..summary = SalesSummary(
      from: _stamp(today.subtract(const Duration(days: 29))),
      to: _stamp(today),
      totalTransactions: 8,
      totalGross: 5500,
      totalVat: 0,
      totalDiscounts: 0,
      days: [
        day(10, transactions: 5, gross: 4000),
        day(1, transactions: 1, gross: 500),
        day(0, transactions: 2, gross: 1000),
      ],
    );
}

void main() {
  group('AdminSalesChart', () {
    testWidgets('an all-zero week renders flat bars instead of red-screening', (
      tester,
    ) async {
      _sizeUp(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdminSalesChart(
              values: [0.0, 0.0, 0.0],
              labels: ['a', 'b', 'c'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AdminSalesChart), findsOneWidget);
    });

    testWidgets('a refund-heavy negative day clamps instead of red-screening', (
      tester,
    ) async {
      _sizeUp(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdminSalesChart(values: [1000.0, -200.0], labels: ['a', 'b']),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AdminSalesChart), findsOneWidget);
    });

    testWidgets('a bar fills its slot and its height follows the value', (
      tester,
    ) async {
      _sizeUp(tester);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AdminSalesChart(values: [1000.0, 500.0], labels: ['a', 'b']),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final tallest = tester.getSize(
        find.byKey(const ValueKey('admin-sales-chart-bar-0')),
      );
      final half = tester.getSize(
        find.byKey(const ValueKey('admin-sales-chart-bar-1')),
      );
      // Was 0 wide before: a FractionallySizedBox without a width factor hands
      // its child loose width, and a box with no child collapses to nothing, so
      // the screen drew labels over an empty chart.
      expect(tallest.width, greaterThan(0));
      expect(half.width, greaterThan(0));
      expect(half.height, closeTo(tallest.height / 2, 1));
      // Seven bars across a wide window would be 120 px slabs: a bar keeps a
      // chart's width even when its slot grows.
      expect(tallest.width, lessThanOrEqualTo(56));
    });

    testWidgets(
      'thirty bars at 760 px thin their labels instead of overlapping',
      (tester) async {
        tester.view.physicalSize = const Size(760, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AdminSalesChart(
                values: [for (var i = 0; i < 30; i++) 100.0 + i],
                // Full dates, the way the page labels its days (D6).
                labels: [for (var i = 0; i < 30; i++) 'Oct ${i + 1}, 2026'],
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // 760 px over 30 bars leaves 25 px each, so only the labels that fit are
        // painted. The newest day always keeps its label.
        expect(
          find.text('Oct 30, 2026'),
          findsOneWidget,
          reason: 'the newest day always keeps its label',
        );
        expect(
          find.textContaining(', 2026').evaluate().length,
          lessThan(30),
          reason: 'every label would be painted on top of its neighbour',
        );
      },
    );
  });

  group('SalesMonitoringPage', () {
    testWidgets('it renders a loading state before the data lands', (
      tester,
    ) async {
      _sizeUp(tester);
      final repository = _monthOfSales();
      await tester.pumpWidget(
        _app(SalesMonitoringPage(repository: repository)),
      );
      // First frame only: the fetch is triggered from a post-frame callback.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('the period chips sit in the FilterBar and name the range', (
      tester,
    ) async {
      _sizeUp(tester);
      await tester.pumpWidget(
        _app(SalesMonitoringPage(repository: _monthOfSales())),
      );
      await tester.pumpAndSettle();

      for (final chip in const ['Today', 'Last 7 days', 'Last 30 days']) {
        expect(
          find.descendant(
            of: find.byType(FilterBar),
            matching: find.text(chip),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('the page says the numbers cover the rows it already loaded', (
      tester,
    ) async {
      _sizeUp(tester);
      await tester.pumpWidget(
        _app(SalesMonitoringPage(repository: _monthOfSales())),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('not a new fetch'), findsOneWidget);
    });

    testWidgets('one read covers thirty days, and the default is seven', (
      tester,
    ) async {
      _sizeUp(tester);
      final repository = _monthOfSales();
      await tester.pumpWidget(
        _app(SalesMonitoringPage(repository: repository)),
      );
      await tester.pumpAndSettle();

      final today = DateTime.now();
      expect(repository.salesCalls, 1);
      expect(repository.lastTo, _stamp(today));
      expect(
        repository.lastFrom,
        _stamp(today.subtract(const Duration(days: 29))),
        reason:
            'the chips filter loaded rows, so the read has to carry 30 days',
      );
      // Default period: today and yesterday (1,000 + 500).
      expect(_tileValue('Gross sales', '₱1,500.00'), findsOneWidget);
      expect(_tileValue('Transactions', '3'), findsOneWidget);
      expect(_tileValue('Average sale', '₱500.00'), findsOneWidget);
      // The chart's money figure is a real peso amount, not a "₱1.0k" label.
      expect(
        find.text('Highest day ${formatPeso(1000)}'),
        findsOneWidget,
        reason: '₱1,000.00, never a rounded thousand-k label',
      );
    });

    testWidgets('a chip narrows the loaded days without another read', (
      tester,
    ) async {
      _sizeUp(tester);
      final repository = _monthOfSales();
      await tester.pumpWidget(
        _app(SalesMonitoringPage(repository: repository)),
      );
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(FilterBar),
          matching: find.text('Today'),
        ),
      );
      await tester.pumpAndSettle();

      expect(_tileValue('Gross sales', '₱1,000.00'), findsOneWidget);
      expect(_tileValue('Transactions', '2'), findsOneWidget);
      expect(_tileValue('Average sale', '₱500.00'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(FilterBar),
          matching: find.text('Last 30 days'),
        ),
      );
      await tester.pumpAndSettle();

      expect(_tileValue('Gross sales', '₱5,500.00'), findsOneWidget);
      expect(repository.salesCalls, 1, reason: 'the chips must not re-fetch');
    });

    testWidgets('the chart is fed the days the server returned', (
      tester,
    ) async {
      _sizeUp(tester);
      final today = DateTime.now();
      await tester.pumpWidget(
        _app(SalesMonitoringPage(repository: _monthOfSales())),
      );
      await tester.pumpAndSettle();

      final chart = tester.widget<AdminSalesChart>(
        find.byType(AdminSalesChart),
      );
      // Seven-day default: yesterday then today, oldest first.
      expect(chart.values, [500.0, 1000.0]);
      expect(chart.labels, [
        formatDate(today.subtract(const Duration(days: 1))),
        formatDate(today),
      ]);
    });

    testWidgets('a search narrows the days on screen', (tester) async {
      _sizeUp(tester);
      final today = DateTime.now();
      await tester.pumpWidget(
        _app(SalesMonitoringPage(repository: _monthOfSales())),
      );
      await tester.pumpAndSettle();

      // The ten-day-old day is outside the default seven-day chip, so widen the
      // range first: the search narrows what the chip left, it does not widen it.
      await tester.tap(
        find.descendant(
          of: find.byType(FilterBar),
          matching: find.text('Last 30 days'),
        ),
      );
      await tester.pumpAndSettle();
      expect(_tileValue('Gross sales', '₱5,500.00'), findsOneWidget);

      await tester.enterText(
        find.descendant(
          of: find.byType(FilterBar),
          matching: find.byType(TextField),
        ),
        formatDate(today.subtract(const Duration(days: 10))),
      );
      await tester.pumpAndSettle();

      expect(_tileValue('Gross sales', '₱4,000.00'), findsOneWidget);
      expect(_tileValue('Transactions', '5'), findsOneWidget);
    });

    testWidgets('a failure names itself and the retry re-fetches', (
      tester,
    ) async {
      _sizeUp(tester);
      final repository = _monthOfSales()
        ..failure = 'The sales summary could not be loaded.';
      await tester.pumpWidget(
        _app(SalesMonitoringPage(repository: repository)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(
        find.text('The sales summary could not be loaded.'),
        findsOneWidget,
      );
      expect(
        find.byType(AdminSalesChart),
        findsNothing,
        reason: 'a failed load must not render a chart of nothing',
      );

      repository.failure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(repository.salesCalls, 2);
      expect(find.byType(AdminSalesChart), findsOneWidget);
      expect(find.byType(ErrorBanner), findsNothing);
    });

    testWidgets('a range with no sales says so instead of crashing', (
      tester,
    ) async {
      _sizeUp(tester);
      final repository = _monthOfSales()
        ..summary = const SalesSummary(
          from: '2026-10-14',
          to: '2026-10-20',
          totalTransactions: 0,
          totalGross: 0,
          totalVat: 0,
          totalDiscounts: 0,
          days: [],
        );
      await tester.pumpWidget(
        _app(SalesMonitoringPage(repository: repository)),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_salesEmpty), findsOneWidget);
      expect(
        find.byType(AdminSalesChart),
        findsNothing,
        reason: 'AdminSalesChart.reduce throws on an empty list',
      );
    });
  });

  group('InventoryMonitoringPage', () {
    testWidgets('it renders a loading state before the data lands', (
      tester,
    ) async {
      _sizeUp(tester);
      await tester.pumpWidget(
        _app(
          InventoryMonitoringPage(repository: _StubReportsRepository()),
          // Unloaded stock: the state a real visit starts in, where neither
          // read has answered yet.
          inventory: _unloadedStock(),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(_lowOutPanel), findsOneWidget);
    });

    testWidgets('the tiles read the server valuation and the loaded stock', (
      tester,
    ) async {
      _sizeUp(tester);
      await tester.pumpWidget(
        _app(InventoryMonitoringPage(repository: _StubReportsRepository())),
      );
      await tester.pumpAndSettle();

      expect(_tileValue('Total items', '1,200'), findsOneWidget);
      expect(_tileValue('Total cost value', '₱5,000.00'), findsOneWidget);
      expect(_tileValue('Total retail value', '₱8,000.00'), findsOneWidget);
      expect(_tileValue('Low stock', '1'), findsOneWidget);
      expect(_tileValue('Out of stock', '1'), findsOneWidget);
    });

    testWidgets('the low and out list leads with out of stock', (tester) async {
      _sizeUp(tester);
      await tester.pumpWidget(
        _app(InventoryMonitoringPage(repository: _StubReportsRepository())),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_lowOutPanel), findsOneWidget);

      final outOfStock = tester.getTopLeft(
        find.descendant(
          of: find.byKey(_lowOutPanel),
          matching: find.text('Marine Plywood 3/4 in x 4 ft x 8 ft'),
        ),
      );
      final low = tester.getTopLeft(
        find.descendant(
          of: find.byKey(_lowOutPanel),
          matching: find.text('Portland Cement'),
        ),
      );
      expect(
        outOfStock.dy,
        lessThan(low.dy),
        reason: 'nothing on the shelf is the row an owner acts on first',
      );

      expect(
        find.descendant(
          of: find.byKey(_lowOutPanel),
          matching: find.byType(StatusBadge),
        ),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: find.byKey(_lowOutPanel),
          matching: find.text('Out of stock'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(_lowOutPanel),
          matching: find.text('Low stock'),
        ),
        findsOneWidget,
      );
      // Quantities go through `formatQuantity`, and a low row says what it is
      // low against.
      expect(
        find.descendant(
          of: find.byKey(_lowOutPanel),
          matching: find.text(formatQuantity(12)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(_lowOutPanel),
          matching: find.text('left of ${formatQuantity(30)}'),
        ),
        findsOneWidget,
      );
      // A healthy variant is not a row of this list.
      expect(
        find.descendant(
          of: find.byKey(_lowOutPanel),
          matching: find.text('Fill Sand'),
        ),
        findsNothing,
      );
    });

    testWidgets('the highest value stock ranks by value at landed cost', (
      tester,
    ) async {
      _sizeUp(tester);
      await tester.pumpWidget(
        _app(InventoryMonitoringPage(repository: _StubReportsRepository())),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(_valuePanel), findsOneWidget);

      final top = tester.getTopLeft(
        find.descendant(
          of: find.byKey(_valuePanel),
          matching: find.text('Portland Cement'),
        ),
      );
      final next = tester.getTopLeft(
        find.descendant(
          of: find.byKey(_valuePanel),
          matching: find.text('Fill Sand'),
        ),
      );
      expect(top.dy, lessThan(next.dy));
      expect(
        find.descendant(
          of: find.byKey(_valuePanel),
          matching: find.text('₱2,160.00'),
        ),
        findsOneWidget,
        reason: '12 bags at 180.00 landed cost',
      );
      expect(
        find.descendant(
          of: find.byKey(_valuePanel),
          matching: find.text(formatQuantity(900)),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a failed first load is one banner, not a banner and a list', (
      tester,
    ) async {
      _sizeUp(tester);
      SharedPreferences.setMockInitialValues({});
      final products = _FailingProductsRepository();
      final stock = InventoryViewmodel(
        products: products,
        inventory: FakeInventoryRepository(),
        catalogue: FakeCatalogueRepository(),
      );
      final repository = _StubReportsRepository()
        ..failure = 'The inventory valuation could not be loaded.';
      await tester.pumpWidget(
        _app(InventoryMonitoringPage(repository: repository), inventory: stock),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ErrorBanner), findsOneWidget);
      expect(
        find.text('The inventory valuation could not be loaded.'),
        findsOneWidget,
      );
      expect(
        find.byKey(_lowOutPanel),
        findsNothing,
        reason: 'a failed read must not render an empty list under the banner',
      );
      expect(
        find.byKey(_valuePanel),
        findsNothing,
        reason: 'a failed read must not render an empty list under the banner',
      );

      // The retry re-reads BOTH sources, so both have to recover for the screen
      // to clear its banner.
      repository.failure = null;
      products.failing = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(repository.valuationCalls, 2);
      expect(products.attempts, 2, reason: 'the stock read is retried too');
      expect(find.byType(ErrorBanner), findsNothing);
      expect(find.byKey(_lowOutPanel), findsOneWidget);
    });
  });
}
