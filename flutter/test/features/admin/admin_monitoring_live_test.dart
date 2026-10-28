// Decision D-03 (sales-manager-workflow): both admin monitoring pages rendered
// `AdminMockData` — a fake weekly chart and four fake inventory tiles, sitting
// in the admin shell next to screens that show real money. A manager reading
// "P1 240 000 gross" off invented bars is worse than reading nothing.
//
// The replacement is `ReportsRepository`, which already had both endpoints.
// These tests pin:
//   * the chart receives EXACTLY the days the repository returned (no re-derivation),
//   * the summary row shows the server's totals,
//   * a failure names itself and offers a retry that actually re-fetches,
//   * an empty range says "no data" instead of crashing in `AdminSalesChart`,
//     whose `values.reduce` throws on an empty list.
//
// Both pages build their own repository in production, so the injected seam is
// what makes these states renderable at all.

import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/features/admin/views/inventory_monitoring_page.dart';
import 'package:client/features/admin/views/sales_monitoring_page.dart';
import 'package:client/features/admin/widgets/admin_inventory_summary.dart';
import 'package:client/features/admin/widgets/admin_sales_chart.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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
    totalTransactions: 12,
    totalGross: 4500,
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
    batchCount: 7,
    totalUnits: 120,
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

Widget _app(Widget child) => ChangeNotifierProvider<AuthViewmodel>.value(
  value: AuthViewmodel(AuthRepository(AuthService())),
  child: MaterialApp(home: child),
);

void _sizeUp(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
            body: AdminSalesChart(
              values: [1000.0, -200.0],
              labels: ['a', 'b'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AdminSalesChart), findsOneWidget);
    });
  });

  group('SalesMonitoringPage', () {
    testWidgets('it renders a loading state before the data lands', (
      tester,
    ) async {
      _sizeUp(tester);
      final repository = _StubReportsRepository();
      await tester.pumpWidget(
        _app(SalesMonitoringPage(repository: repository)),
      );
      // First frame only: the fetch is triggered from a post-frame callback.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('the chart is fed the days the server returned', (
      tester,
    ) async {
      _sizeUp(tester);
      final repository = _StubReportsRepository();
      await tester.pumpWidget(
        _app(SalesMonitoringPage(repository: repository)),
      );
      await tester.pumpAndSettle();

      final chart = tester.widget<AdminSalesChart>(
        find.byType(AdminSalesChart),
      );
      expect(chart.values, [1000.0, 2500.0]);
      expect(chart.labels, ['2026-10-19', '2026-10-20']);
    });

    testWidgets('the summary row shows the server totals', (tester) async {
      _sizeUp(tester);
      await tester.pumpWidget(
        _app(SalesMonitoringPage(repository: _StubReportsRepository())),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<Text>(
              find.byKey(const Key('sales-monitoring-transactions')),
            )
            .data,
        '12',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const Key('sales-monitoring-gross')))
            .data,
        '₱4500.00',
      );
    });

    testWidgets('the default range is the last seven days', (tester) async {
      _sizeUp(tester);
      final repository = _StubReportsRepository();
      await tester.pumpWidget(
        _app(SalesMonitoringPage(repository: repository)),
      );
      await tester.pumpAndSettle();

      final today = DateTime.now();
      String stamp(DateTime day) =>
          '${day.year.toString().padLeft(4, '0')}-'
          '${day.month.toString().padLeft(2, '0')}-'
          '${day.day.toString().padLeft(2, '0')}';

      expect(repository.lastTo, stamp(today));
      expect(
        repository.lastFrom,
        stamp(today.subtract(const Duration(days: 6))),
      );
    });

    testWidgets('a failure names itself and the retry re-fetches', (
      tester,
    ) async {
      _sizeUp(tester);
      final repository = _StubReportsRepository()
        ..failure = 'The sales summary could not be loaded.';
      await tester.pumpWidget(
        _app(SalesMonitoringPage(repository: repository)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LiveLoadErrorBanner), findsOneWidget);
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
      expect(find.byType(LiveLoadErrorBanner), findsNothing);
    });

    testWidgets('a range with no sales says so instead of crashing', (
      tester,
    ) async {
      _sizeUp(tester);
      final repository = _StubReportsRepository()
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

      expect(find.byKey(const Key('sales-monitoring-empty')), findsOneWidget);
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
        _app(InventoryMonitoringPage(repository: _StubReportsRepository())),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('the tiles come from the valuation, not the mock data', (
      tester,
    ) async {
      _sizeUp(tester);
      await tester.pumpWidget(
        _app(InventoryMonitoringPage(repository: _StubReportsRepository())),
      );
      await tester.pumpAndSettle();

      final summary = tester.widget<AdminInventorySummary>(
        find.byType(AdminInventorySummary),
      );
      expect(summary.metrics, [
        ('Total items', '120'),
        ('Total cost value', '₱5000.00'),
        ('Total retail value', '₱8000.00'),
        ('Batches', '7'),
      ]);
    });

    testWidgets('a failure names itself and the retry re-fetches', (
      tester,
    ) async {
      _sizeUp(tester);
      final repository = _StubReportsRepository()
        ..failure = 'The inventory valuation could not be loaded.';
      await tester.pumpWidget(
        _app(InventoryMonitoringPage(repository: repository)),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LiveLoadErrorBanner), findsOneWidget);
      expect(
        find.byType(AdminInventorySummary),
        findsNothing,
        reason: 'a failed load must not render zeroed tiles',
      );

      repository.failure = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(repository.valuationCalls, 2);
      expect(find.byType(AdminInventorySummary), findsOneWidget);
    });
  });
}
