// The Store Manager approves requisitions and manages staff (decisions 16 and
// 20), but until 2026-10-30 nothing in their screens led there: the screens
// were only reachable by typing /admin/... and then showed the ADMIN sidebar.
// The same fix as Reports (D-01): sales-shell pages at /sales/requisitions and
// /sales/staff, appended to the sales sidebar as indexes 7 and 8.

import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/user_service.dart';
import 'package:client/features/admin/viewmodels/admin_requisitions_viewmodel.dart';
import 'package:client/features/admin/viewmodels/admin_users_viewmodel.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/sales/views/sales_requisitions_page.dart';
import 'package:client/features/sales/views/sales_staff_page.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class _StubRequisitions extends RequisitionRepository {
  @override
  Future<List<Requisition>> fetchRequisitions() async => const [];
}

class _StubUsers extends UserService {
  _StubUsers() : super();

  @override
  Future<List<User>> fetchUsers({String? search}) async => const [];

  @override
  Future<UserStats> fetchUserStats() async =>
      const UserStats(total: 0, active: 0, inactive: 0, rolesAssigned: 0);
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapNavigation(WidgetTester tester, int index) async {
  final router = GoRouter(
    initialLocation: '/start',
    routes: [
      GoRoute(
        path: '/start',
        builder: (context, state) => Scaffold(
          body: TextButton(
            onPressed: () => navigateSales(context, index),
            child: const Text('navigate'),
          ),
        ),
      ),
      for (final path in [AppRoutes.salesRequisitions, AppRoutes.salesStaff])
        GoRoute(
          path: path,
          builder: (context, state) => Scaffold(body: Text('page:$path')),
        ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('navigate'));
  await tester.pumpAndSettle();
}

void main() {
  test('the routes are /sales/requisitions and /sales/staff', () {
    expect(AppRoutes.salesRequisitions, '/sales/requisitions');
    expect(AppRoutes.salesStaff, '/sales/staff');
  });

  test('the sales sidebar offers Approvals (7) and Staff (8)', () {
    final labels = SalesSkeletonLayout.navigationSections
        .expand((section) => section.destinations)
        .map((destination) => destination.label)
        .toList();
    expect(labels.indexOf('Approvals'), 7);
    expect(labels.indexOf('Staff'), 8);
  });

  testWidgets('index 7 goes to the approval queue', (tester) async {
    await _tapNavigation(tester, 7);
    expect(find.text('page:/sales/requisitions'), findsOneWidget);
  });

  testWidgets('index 8 goes to staff', (tester) async {
    await _tapNavigation(tester, 8);
    expect(find.text('page:/sales/staff'), findsOneWidget);
  });

  test('only the Store Manager is admitted to the new routes', () {
    for (final location in [
      AppRoutes.salesRequisitions,
      AppRoutes.salesStaff,
    ]) {
      expect(
        AppRoutes.redirectFor(
          isAuthenticated: true,
          role: 'sales',
          location: location,
        ),
        isNull,
        reason: 'the manager stays on $location',
      );
      expect(
        AppRoutes.redirectFor(
          isAuthenticated: true,
          role: 'pos',
          location: location,
        ),
        AppRoutes.posDashboard,
      );
      expect(
        AppRoutes.redirectFor(
          isAuthenticated: true,
          role: 'inventory',
          location: location,
        ),
        AppRoutes.inventoryDashboard,
      );
    }
  });

  testWidgets('Approvals keeps the SALES sidebar', (tester) async {
    await _pump(
      tester,
      SalesRequisitionsPage(
        viewmodel: AdminRequisitionsViewmodel(repository: _StubRequisitions()),
      ),
    );

    final layout = tester.widget<SalesSkeletonLayout>(
      find.byType(SalesSkeletonLayout),
    );
    expect(layout.selectedNavigationIndex, 7);
    expect(layout.onNavigationSelected, isNotNull);
    expect(find.byType(AdminSkeletonLayout), findsNothing);
  });

  testWidgets('Staff keeps the SALES sidebar', (tester) async {
    await _pump(
      tester,
      SalesStaffPage(viewmodel: AdminUsersViewmodel(users: _StubUsers())),
    );

    final layout = tester.widget<SalesSkeletonLayout>(
      find.byType(SalesSkeletonLayout),
    );
    expect(layout.selectedNavigationIndex, 8);
    expect(layout.onNavigationSelected, isNotNull);
    expect(find.byType(AdminSkeletonLayout), findsNothing);
  });
}
