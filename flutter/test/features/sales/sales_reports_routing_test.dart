// Decision D-01 (sales-manager-workflow): the sales sidebar's Reports tab is
// index 6, and `navigateSales` only covered 0-5 — so tapping Reports was a
// SILENT no-op. Nothing failed, nothing logged; the manager simply pressed a
// button that did nothing.
//
// Two properties are pinned here:
//   1. The route exists AND index 6 of `navigateSales` actually arrives there.
//      Asserted through a real GoRouter, because the bug was in the navigation
//      call, not in the constant.
//   2. The page the manager lands on is wrapped in the SALES shell, not the
//      admin one (decision D-01 option B). Reusing `ReportsPage` directly would
//      compile and pass a routing test while swapping the sidebar out from
//      under the manager.

import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/admin/viewmodels/admin_reports_viewmodel.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/sales/views/sales_reports_page.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// The sales sidebar's destinations in side-bar order. Restated here on
/// purpose: this list is the contract the sidebar and `navigateSales` must
/// agree on, so a drift in either shows up as a failure rather than as a
/// button that does nothing.
const _salesPaths = [
  '/sales/dashboard',
  '/sales/transactions',
  '/sales/quotations',
  '/sales/orders',
  '/sales/receivables',
  '/sales/returns',
  '/sales/reports',
];

Widget _app(Widget child) => ChangeNotifierProvider<AuthViewmodel>.value(
  value: AuthViewmodel(AuthRepository(AuthService())),
  child: MaterialApp(home: child),
);

class _StubReportsRepository extends ReportsRepository {
  _StubReportsRepository() : super();

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
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
      totalIn: 0,
      totalOut: 0,
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

/// Pumps a two-screen router: a launch screen with one button that calls
/// `navigateSales(context, index)`, and a placeholder page per known path.
Future<void> _tapNavigation(WidgetTester tester, int index) async {
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (context, state) => Scaffold(
          body: TextButton(
            key: const Key('navigate'),
            onPressed: () => navigateSales(context, index),
            child: const Text('navigate'),
          ),
        ),
      ),
      for (final path in _salesPaths)
        GoRoute(
          path: path,
          builder: (context, state) => Scaffold(body: Text('page:$path')),
        ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.byKey(const Key('navigate')));
  await tester.pumpAndSettle();
}

void main() {
  test('salesReports is /sales/reports', () {
    expect(AppRoutes.salesReports, '/sales/reports');
  });

  test('the sales sidebar has seven destinations', () {
    expect(
      SalesSkeletonLayout.navigationSections
          .expand((section) => section.destinations)
          .length,
      7,
      reason: 'index 6 (Reports) is only reachable if the sidebar renders it',
    );
  });

  group('navigateSales covers every sidebar index', () {
    for (var index = 0; index < _salesPaths.length; index++) {
      testWidgets('index $index goes to ${_salesPaths[index]}', (tester) async {
        await _tapNavigation(tester, index);
        expect(find.text('page:${_salesPaths[index]}'), findsOneWidget);
      });
    }
  });

  testWidgets('Reports lands in the SALES shell, not the admin one', (
    tester,
  ) async {
    _sizeUp(tester);
    await tester.pumpWidget(
      _app(
        SalesReportsPage(
          viewmodel: AdminReportsViewmodel(
            repository: _StubReportsRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final layout = tester.widget<SalesSkeletonLayout>(
      find.byType(SalesSkeletonLayout),
    );
    expect(layout.title, 'Reports');
    expect(
      layout.selectedNavigationIndex,
      6,
      reason: 'Reports is index 6 of the sales sidebar',
    );
    expect(
      layout.onNavigationSelected,
      isNotNull,
      reason: 'without this the sidebar stops navigating on the Reports tab',
    );
    expect(
      find.byType(AdminSkeletonLayout),
      findsNothing,
      reason:
          'the manager must not lose the sales sidebar on the Reports tab '
          '(decision D-01 option B)',
    );
  });

  testWidgets('the four report tabs render inside the sales shell', (
    tester,
  ) async {
    _sizeUp(tester);
    await tester.pumpWidget(
      _app(
        SalesReportsPage(
          viewmodel: AdminReportsViewmodel(
            repository: _StubReportsRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final tabBar = find.byType(TabBar);
    for (final tab in ['Sales', 'Valuation', 'Movements', 'Requisitions']) {
      expect(
        find.descendant(of: tabBar, matching: find.text(tab)),
        findsOneWidget,
        reason: '$tab must be reachable from the sales shell too',
      );
    }
    expect(
      find.text('Gross sales'),
      findsOneWidget,
      reason: 'the Sales tab must render live data, not an empty shell',
    );
  });
}
