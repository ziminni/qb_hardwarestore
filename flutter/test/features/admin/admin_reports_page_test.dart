// Decision 16 (as amended): ONE admin Reports screen, four tabs, one report at a time.

import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/features/admin/viewmodels/admin_reports_viewmodel.dart';
import 'package:client/features/admin/views/reports_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _app(Widget child) => ChangeNotifierProvider<AuthViewmodel>.value(
  value: AuthViewmodel(AuthRepository(AuthService())),
  child: MaterialApp(home: child),
);

class _StubReportsRepository extends ReportsRepository {
  _StubReportsRepository() : super();

  int salesCalls = 0;
  int valuationCalls = 0;
  String? lastFrom;
  String? lastTo;
  bool failSales = false;

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
    salesCalls++;
    lastFrom = from;
    lastTo = to;
    if (failSales) {
      throw const ReportsServiceException(
        'The sales summary could not be loaded.',
      );
    }
    return const SalesSummary(
      from: '',
      to: '',
      totalTransactions: 3,
      totalGross: 1500,
      totalVat: 0,
      totalDiscounts: 50,
      days: [],
    );
  }

  @override
  Future<InventoryValuation> fetchInventoryValuation() async {
    valuationCalls++;
    return const InventoryValuation(
      batchCount: 2,
      totalUnits: 10,
      totalCost: 500,
      totalRetail: 800,
      categories: [],
    );
  }

  @override
  Future<StockMovements> fetchStockMovements({String? from, String? to}) async {
    return const StockMovements(
      from: '',
      to: '',
      totalIn: 100,
      totalOut: 30,
      receiptsByDay: [],
      adjustmentsByType: [],
    );
  }

  @override
  Future<RequisitionHistory> fetchRequisitionHistory() async {
    return const RequisitionHistory(
      from: '',
      to: '',
      statusFilter: null,
      countByStatus: {},
      requisitions: [],
    );
  }
}

void _sizeUp(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<_StubReportsRepository> _pump(
  WidgetTester tester, {
  bool failSales = false,
}) async {
  _sizeUp(tester);
  final repository = _StubReportsRepository()..failSales = failSales;
  await tester.pumpWidget(
    _app(ReportsPage(viewmodel: AdminReportsViewmodel(repository: repository))),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('four tabs render and the sales totals show', (tester) async {
    await _pump(tester);

    // Scoped to the TabBar: the admin sidebar itself carries an exact
    // "Requisitions" entry, so an unscoped finder matches twice.
    final tabBar = find.byType(TabBar);
    for (final tab in ['Sales', 'Valuation', 'Movements', 'Requisitions']) {
      expect(
        find.descendant(of: tabBar, matching: find.text(tab)),
        findsOneWidget,
      );
    }
    expect(find.textContaining('1,500'), findsWidgets);
  });

  testWidgets('selecting valuation loads it once', (tester) async {
    final repository = await _pump(tester);

    await tester.tap(find.text('Valuation'));
    await tester.pumpAndSettle();

    expect(repository.valuationCalls, 1);
    expect(find.textContaining('500'), findsWidgets);
  });

  testWidgets('a failed sales tab names the failure and keeps the other tabs', (
    tester,
  ) async {
    await _pump(tester, failSales: true);

    expect(find.textContaining('could not be loaded'), findsOneWidget);

    await tester.tap(find.text('Movements'));
    await tester.pumpAndSettle();

    expect(find.textContaining('could not be loaded'), findsNothing);
  });

  testWidgets('a bad date is refused without posting', (tester) async {
    final repository = await _pump(tester);

    await tester.enterText(find.byKey(const Key('reports-from')), 'not-a-date');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(find.text('Enter dates as YYYY-MM-DD.'), findsOneWidget);
    expect(repository.salesCalls, 1);
  });

  testWidgets('a range change reloads sales with the new bounds', (
    tester,
  ) async {
    final repository = await _pump(tester);

    await tester.enterText(find.byKey(const Key('reports-from')), '2026-01-01');
    await tester.enterText(find.byKey(const Key('reports-to')), '2026-01-31');
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(repository.salesCalls, 2);
    expect(repository.lastFrom, '2026-01-01');
    expect(repository.lastTo, '2026-01-31');
  });
}
