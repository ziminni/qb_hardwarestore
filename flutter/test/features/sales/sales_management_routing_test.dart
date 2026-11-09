// The Store Manager manages staff from their own shell (decisions 16 and 20),
// the same fix as Reports (D-01): a sales-shell page at /sales/staff, appended
// to the sales sidebar.
//
// Decision 01 (2026-11-03) removed the Approvals entry that used to sit at
// index 7: requests are approved in CPMS, so the POS has no queue. Staff moved
// up into the slot the queue left free.

import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/user_service.dart';
import 'package:client/features/admin/viewmodels/admin_users_viewmodel.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/sales/views/sales_staff_page.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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
      GoRoute(
        path: AppRoutes.salesStaff,
        builder: (context, state) =>
            const Scaffold(body: Text('page:/sales/staff')),
      ),
    ],
  );
  await tester.pumpWidget(MaterialApp.router(routerConfig: router));
  await tester.tap(find.text('navigate'));
  await tester.pumpAndSettle();
}

void main() {
  test('the route is /sales/staff', () {
    expect(AppRoutes.salesStaff, '/sales/staff');
  });

  test('the sales sidebar offers Staff at 7, with no Approvals entry', () {
    final labels = SalesSkeletonLayout.navigationSections
        .expand((section) => section.destinations)
        .map((destination) => destination.label)
        .toList();
    expect(labels.indexOf('Staff'), 7);
    expect(labels, isNot(contains('Approvals')));
    // Phase 1b appended the store-review queue after Staff, in its own section.
    expect(labels.indexOf('Requests from projects'), 8);
    expect(labels, hasLength(9));
  });

  testWidgets('index 7 goes to staff', (tester) async {
    await _tapNavigation(tester, 7);
    expect(find.text('page:/sales/staff'), findsOneWidget);
  });

  test('only the Store Manager is admitted to the staff screen', () {
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: 'sales',
        location: AppRoutes.salesStaff,
      ),
      isNull,
      reason: 'the manager stays on their staff list',
    );
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: 'pos',
        location: AppRoutes.salesStaff,
      ),
      AppRoutes.posDashboard,
    );
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: 'inventory',
        location: AppRoutes.salesStaff,
      ),
      AppRoutes.inventoryDashboard,
    );
  });

  testWidgets('Staff keeps the SALES sidebar', (tester) async {
    await _pump(
      tester,
      SalesStaffPage(viewmodel: AdminUsersViewmodel(users: _StubUsers())),
    );

    final layout = tester.widget<SalesSkeletonLayout>(
      find.byType(SalesSkeletonLayout),
    );
    expect(layout.selectedNavigationIndex, 7);
    expect(layout.onNavigationSelected, isNotNull);
    expect(find.byType(AdminSkeletonLayout), findsNothing);
  });
}
