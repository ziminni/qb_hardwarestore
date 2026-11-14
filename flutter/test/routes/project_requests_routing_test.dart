// Phase 1b Task 7: "Requests from projects" is ONE screen body with two thin
// role shells, reached at /sales/project-requests (Store Manager) and
// /admin/project-requests (Admin, plus the manager's typed admin URL through
// `salesTwinOf`). Cashier and Stock Manager have no entry and no door.
//
// The retired approval URLs stay retired (decision 01): /admin/requisitions and
// /sales/requisitions must keep bouncing exactly like any unknown address, which
// `admin_requisitions_routing_test.dart` already pins.
import 'dart:io';

import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/requisitions/views/project_requests_page.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

AuthViewmodel _auth(String role, String roleLabel) {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  auth.user = User(
    id: 1,
    username: role,
    email: '$role@qb.local',
    fullName: 'Test $roleLabel',
    role: Role(id: 1, name: role, displayName: roleLabel),
  );
  return auth;
}

String? _redirect(String role, String location) => AppRoutes.redirectFor(
  isAuthenticated: true,
  role: role,
  location: location,
);

/// Pumps one of the two shells. The page builds its own viewmodel, whose reads
/// fail without a server — the shell is what this file checks, and the queue
/// behind it reports its own error (the page test covers that).
Future<void> _pumpPage(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: _auth('admin', 'Admin'),
      child: MaterialApp(home: page),
    ),
  );
  await tester.pumpAndSettle();
}

/// The labels of one shell's sidebar, in flat index order.
List<String> _labels(List<dynamic> sections) => [
  for (final section in sections)
    for (final destination in section.destinations) destination.label as String,
];

void main() {
  test('the two routes are appended under the existing areas', () {
    expect(AppRoutes.salesProjectRequests, '/sales/project-requests');
    expect(AppRoutes.adminProjectRequests, '/admin/project-requests');
  });

  test('the manager typing the admin URL lands on the sales twin', () {
    expect(
      AppRoutes.salesTwinOf('/admin/project-requests'),
      '/sales/project-requests',
    );
    expect(
      _redirect('sales', '/admin/project-requests'),
      '/sales/project-requests',
    );
  });

  test('only the Store Manager and the Admin reach the queue', () {
    expect(_redirect('sales', '/sales/project-requests'), isNull);
    expect(_redirect('admin', '/admin/project-requests'), isNull);

    // Cashier and Stock Manager: no entry, and a typed URL goes to their own
    // dashboard rather than to a screen they may not use.
    expect(_redirect('pos', '/sales/project-requests'), AppRoutes.posDashboard);
    expect(_redirect('pos', '/admin/project-requests'), AppRoutes.posDashboard);
    expect(
      _redirect('inventory', '/sales/project-requests'),
      AppRoutes.inventoryDashboard,
    );
    expect(
      _redirect('inventory', '/admin/project-requests'),
      AppRoutes.inventoryDashboard,
    );
    // The admin area stays admin-only: the manager's door is the twin, and the
    // cashier's own shell is not a way into the admin queue.
    expect(
      _redirect('admin', '/sales/project-requests'),
      AppRoutes.adminDashboard,
    );
  });

  test('the sales sidebar appends the queue at index 8, after Staff', () {
    final labels = _labels(SalesSkeletonLayout.navigationSections);
    expect(labels.indexOf('Project requests'), 8);
    expect(labels.indexOf('Staff'), 7, reason: 'no earlier index may move');
    // Phase 5 F2 appended Payables at 9 and F3 appended Deliveries at 10, so
    // the queue is no longer last and the list is one longer each time.
    // Neither earlier index moved.
    expect(labels, hasLength(12));
    expect(labels[9], 'Payables');
    expect(labels[10], 'Deliveries');
    expect(
      labels[11],
      'Transfers',
      reason: 'Phase 9 F3 appends Transfers last; no earlier index may move',
    );
    expect(
      SalesSkeletonLayout.navigationSections
          .map((section) => section.label)
          .toList(),
      contains('Projects'),
      reason:
          'the entry keeps its own section rather than renumbering the rest',
    );
    expect(SalesSkeletonLayout.projectRequestsIndex, 8);
  });

  test('the admin sidebar appends the queue at index 7 in a final group', () {
    const labels = [
      'Overview',
      'User management',
      'Inventory',
      'Sales & POS',
      'Reports',
      'Audit logs',
      'Settings',
      'Project requests',
      'Payables',
      'Deliveries',
      'Storage locations',
      'Transfers',
    ];
    expect(AdminSkeletonLayout.projectRequestsIndex, 7);
    // Phase 5 F2/F3/F4 and Phase 9 F3 appended Payables, Deliveries, Storage
    // locations and Transfers, each in a group of its own, so Projects is now
    // FIFTH from the end; its index is untouched.
    expect(AdminSkeletonLayout.groups[AdminSkeletonLayout.groups.length - 5], (
      'Projects',
      7,
    ));
    expect(AdminSkeletonLayout.groups[AdminSkeletonLayout.groups.length - 4], (
      'Payables',
      8,
    ));
    expect(AdminSkeletonLayout.groups[AdminSkeletonLayout.groups.length - 3], (
      'Deliveries',
      9,
    ));
    expect(AdminSkeletonLayout.groups[AdminSkeletonLayout.groups.length - 2], (
      'Locations',
      10,
    ));
    expect(AdminSkeletonLayout.groups.last, ('Transfers', 11));
    // The group slicing is what actually renders the rows; a restated label list
    // that the layout does not produce would prove nothing.
    final source = File(
      'lib/core/layout/admin_skeleton_layout.dart',
    ).readAsStringSync();
    for (final label in labels) {
      expect(source, contains(label), reason: 'admin menu is missing $label');
    }
    expect(
      AdminSkeletonLayout.groups.map((group) => group.$1),
      contains('Projects'),
    );
  });

  testWidgets('navigateSales sends index 8 to the queue', (tester) async {
    late GoRouter router;
    router = GoRouter(
      initialLocation: '/start',
      routes: [
        GoRoute(
          path: '/start',
          builder: (context, state) => Scaffold(
            body: TextButton(
              onPressed: () => navigateSales(context, 8),
              child: const Text('navigate'),
            ),
          ),
        ),
        GoRoute(
          path: '/sales/project-requests',
          builder: (context, state) => const Scaffold(body: Text('page:queue')),
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('navigate'));
    await tester.pumpAndSettle();
    expect(find.text('page:queue'), findsOneWidget);
    router.dispose();
  });

  test('the router wires both paths to their own page class', () {
    // The redirect tests above prove WHO may go where; this proves the door is
    // there at all, on the same source the router is built from.
    final routes = File('lib/routes/routes.dart').readAsStringSync();
    expect(
      RegExp(
        r'path:\s*adminProjectRequests,[\s\S]{0,220}?const AdminProjectRequestsPage\(\)',
      ).hasMatch(routes),
      isTrue,
    );
    expect(
      RegExp(
        r'path:\s*salesProjectRequests,[\s\S]{0,220}?const ProjectRequestsPage\(\)',
      ).hasMatch(routes),
      isTrue,
    );
    expect(routes, isNot(contains("'/admin/requisitions'")));
    expect(routes, isNot(contains("'/sales/requisitions'")));
  });

  testWidgets('the admin page renders the admin shell on index 7', (
    tester,
  ) async {
    await _pumpPage(tester, const AdminProjectRequestsPage());

    final layout = tester.widget<AdminSkeletonLayout>(
      find.byType(AdminSkeletonLayout),
    );
    expect(layout.title, 'Requests from projects');
    expect(
      layout.selectedNavigationIndex,
      AdminSkeletonLayout.projectRequestsIndex,
    );
    expect(find.byType(SalesSkeletonLayout), findsNothing);
  });

  testWidgets('the manager page renders the sales shell on index 8', (
    tester,
  ) async {
    await _pumpPage(tester, const ProjectRequestsPage());

    final layout = tester.widget<SalesSkeletonLayout>(
      find.byType(SalesSkeletonLayout),
    );
    expect(layout.title, 'Requests from projects');
    expect(
      layout.selectedNavigationIndex,
      SalesSkeletonLayout.projectRequestsIndex,
    );
    expect(
      layout.onNavigationSelected,
      isNotNull,
      reason: 'without it every sales sidebar tab on this screen is a no-op',
    );
    expect(find.byType(AdminSkeletonLayout), findsNothing);
  });
}
