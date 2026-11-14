// Phase 2 F2: ONE sidebar for an account that holds several areas.
//
// Pinned here, one property per test:
//   * the assigned list is validated and de-duplicated, and the area headings
//     render in Till, Sales, Stock, Admin order (only the held ones);
//   * a page that exists in several areas appears ONCE, under the WIDEST held
//     area, and links to that area's route. De-duplication keys off the shared
//     key, never a label: Stock's own Reports is a different page and survives;
//   * a page wrapped in ANY area's shell highlights its one merged row, and a
//     tap opens the widest area's route;
//   * badges: one query per held area, a shared badge counted once (widest
//     area), a failed loader draws nothing at all, and a page's own live count
//     still wins so resolving the last alert clears the badge on that screen;
//   * full sidebar, icon rail and drawer all show the merged list, and the area
//     switcher is retired for merged accounts ONLY.

import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/navigation/merged_sidebar.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/widget/area_switcher_menu.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/app_shell.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _admin = Role(id: 1, name: 'admin', displayName: 'Admin');
const _sales = Role(id: 2, name: 'sales', displayName: 'Store Manager');
const _inventory = Role(id: 3, name: 'inventory', displayName: 'Stock Manager');
const _pos = Role(id: 4, name: 'pos', displayName: 'Cashier');

User _account(List<Role> roles) => User(
  id: 7,
  username: 'staff7',
  email: 'staff7@demo.ph',
  fullName: 'Staff Seven',
  role: roles.isEmpty ? null : roles.first,
  roles: roles,
);

Future<AuthViewmodel> _auth(List<Role> roles) async {
  final auth = AuthViewmodel(_FakeAuthRepository(_account(roles)));
  await auth.login('staff7', 'demo1234');
  return auth;
}

Future<Map<int, int>> _noMarkers() async => const {};

Widget _cashierShell({int selected = 0}) => DashboardShell(
  title: 'Point of Sale',
  subtitle: 'Shift open',
  selectedNavigationIndex: selected,
  navigationItems: posNavigationItems,
  onNavigationSelected: (_) {},
  loadMarkers: _noMarkers,
  child: const Text('BODY'),
);

Widget _salesShell({int selected = 1, Map<int, int>? markers}) =>
    SalesSkeletonLayout(
      title: 'Store manager',
      subtitle: 'Today',
      selectedNavigationIndex: selected,
      onNavigationSelected: (_) {},
      loadMarkers: _noMarkers,
      markers: markers,
      child: const Text('BODY'),
    );

Widget _inventoryShell({int selected = 0, Map<int, int>? markers}) =>
    InventorySkeletonLayout(
      title: 'Stock manager',
      subtitle: 'Catalogue',
      selectedNavigationIndex: selected,
      onNavigationSelected: (_) {},
      loadMarkers: _noMarkers,
      markers: markers,
      child: const Text('BODY'),
    );

/// F4's combined landing page: it builds AppShell itself, with no selected
/// destination of its own, so the merged menu's landing row is what is lit.
Widget _combinedPage() => AppShell(
  title: 'Home',
  subtitle: 'Needs you',
  sections: const [],
  selectedIndex: 0,
  selectedId: MergedSidebar.combinedDashboardId,
  child: const Text('COMBINED'),
);

Widget _adminShell({int selected = 0}) => AdminSkeletonLayout(
  title: 'Admin',
  subtitle: 'Back office',
  selectedNavigationIndex: selected,
  onNavigationSelected: (_) {},
  loadMarkers: _noMarkers,
  child: const Text('BODY'),
);

Future<void> _pump(
  WidgetTester tester,
  AuthViewmodel auth,
  Widget shell, {
  Size size = const Size(1440, 900),
  Widget Function(Widget shell)? wrap,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final home = wrap == null ? shell : wrap(shell);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: auth,
      child: MaterialApp(theme: AppTheme.lightTheme, home: home),
    ),
  );
  await tester.pumpAndSettle();
}

/// Tall enough to build EVERY merged row: a ListView only builds what fits, and
/// a row that was never built would look like a missing destination. The widths
/// stay the ones the layout tests name (1440 full, 1100 rail, 760 drawer).
const _tall = Size(1440, 1800);
const _tallRail = Size(1100, 1800);

/// The one row carrying [label]. Fails when the label is drawn twice, which is
/// exactly the merged duplicate this file is about.
ListTile _tile(WidgetTester tester, String label) => tester.widget<ListTile>(
  find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
);

/// The labels of the rows a filled sidebar is currently drawing.
List<String> _drawnRows(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(
    find.descendant(
      of: find.byType(SharedSidebar),
      matching: find.byType(ListTile),
    ),
  ))
    if (tile.title case final Text title) title.data!,
];

/// The rows that carry a live count, in drawing order.
List<String> _markedRows(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(
    find.descendant(
      of: find.byType(SharedSidebar),
      matching: find.byType(ListTile),
    ),
  ))
    if (tile.trailing != null && tile.title is Text)
      (tile.title! as Text).data!,
];

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the held area list', () {
    test('drops unknown codes and duplicates, in heading order', () {
      expect(MergedSidebar.heldAreas(const ['sales', 'cpms', 'pos', 'sales']), [
        AppAreas.pos,
        AppAreas.sales,
      ]);
      expect(MergedSidebar.heldAreas(const []), isEmpty);
      expect(MergedSidebar.heldAreas(AppAreas.codes), [
        AppAreas.pos,
        AppAreas.sales,
        AppAreas.inventory,
        AppAreas.admin,
      ]);
    });
  });

  group('the merged rows', () {
    test('Cashier + Store Manager: Till then Sales, every row kept', () {
      final rows = MergedSidebar.rows(const ['pos', 'sales']);

      expect(rows.length, 20, reason: '7 Till rows + 12 Sales rows + landing');
      expect(
        [for (final section in MergedSidebar.sectionsFor(rows)) section.label],
        ['', 'Till', 'Sales'],
      );
      expect(rows.first.id, MergedSidebar.combinedDashboardId);
      expect(
        rows.where((row) => row.id == 'pos.new-transaction').single.id,
        'pos.new-transaction',
      );
      expect(rows.last.id, 'transfers');
      expect(rows.last.area, AppAreas.sales);
    });

    test('Stock + Store Manager: shared pages once, under Sales', () {
      final rows = MergedSidebar.rows(const ['inventory', 'sales']);

      expect(rows.length, 26, reason: '16 Stock + 12 Sales - 3 shared + 1');
      for (final sharedKey in const ['payables', 'deliveries', 'transfers']) {
        final owned = rows.where((row) => row.sharedKey == sharedKey).toList();
        expect(owned.length, 1, reason: '$sharedKey appears once');
        expect(owned.single.area, AppAreas.sales, reason: '$sharedKey: widest');
      }
      // Stock's Reports is InventoryReportsPage, not the Store Manager's Reports
      // page: a different identity, so both stay.
      expect(rows.where((row) => row.id == 'reports').length, 1);
      expect(rows.where((row) => row.id == 'inventory.reports').length, 1);
    });

    test('Admin + Cashier: the till adds no shared page to the admin menu', () {
      final rows = MergedSidebar.rows(const ['admin', 'pos']);

      expect(rows.length, 20, reason: '7 Till + 12 Admin rows + landing');
      expect(
        [for (final section in MergedSidebar.sectionsFor(rows)) section.label],
        ['', 'Till', 'Admin'],
      );
    });

    test('all four areas: 47 rows become 39, every identity once', () {
      final rows = MergedSidebar.rows(AppAreas.codes);

      expect(rows.length, 39);
      expect(rows.map((row) => row.id).toSet().length, 39);
      for (final sharedKey in AppDestinations.sharedIds) {
        expect(
          rows.where((row) => row.sharedKey == sharedKey).length,
          1,
          reason: sharedKey,
        );
      }
      final staff = rows.firstWhere((row) => row.sharedKey == 'staff');
      expect(staff.area, AppAreas.admin);
      expect(staff.label, 'User management', reason: 'Admin label preserved');
      expect(
        [for (final section in MergedSidebar.sectionsFor(rows)) section.label],
        ['', 'Till', 'Sales', 'Stock', 'Admin'],
      );
    });

    test('the landing row: merged only, no area, no heading above it', () {
      final rows = MergedSidebar.rows(const ['pos', 'sales']);
      final landing = rows.first;

      expect(landing.id, 'combined.dashboard');
      expect(landing.label, 'Needs you');
      expect(landing.route, AppRoutes.combinedDashboard);
      expect(
        MergedSidebar.sectionsFor(rows).first.label,
        '',
        reason: 'the landing row sits above the Till heading, unlabelled',
      );
      expect(
        MergedSidebar.sectionsFor(rows).first.destinations.single.id,
        'combined.dashboard',
      );

      // A single-area menu is not merged, so it never grows this row.
      expect(
        MergedSidebar.rows(const ['pos']).map((row) => row.id),
        isNot(contains('combined.dashboard')),
      );
    });

    test('a merged row carries the widest area route, never a twin', () {
      final rows = MergedSidebar.rows(const ['admin', 'inventory']);
      final payables = rows.firstWhere((row) => row.id == 'payables');

      expect(payables.area, AppAreas.admin);
      expect(payables.route, AppRoutes.adminPayables);

      final salesAndStock = MergedSidebar.rows(const ['inventory', 'sales']);
      expect(
        salesAndStock.firstWhere((row) => row.id == 'payables').route,
        AppRoutes.salesPayables,
      );
    });
  });

  group('the merged badges', () {
    test(
      'one query per held area, a shared badge keeps the widest count',
      () async {
        final calls = <String>[];
        Future<int> answer(String area) async {
          calls.add(area);
          return area == AppAreas.admin ? 7 : 4;
        }

        final counts = await MergedSidebar.loadMergedBadges(
          const ['admin', 'sales'],
          loaders: {
            AppAreas.admin: () => answer(AppAreas.admin),
            AppAreas.sales: () => answer(AppAreas.sales),
          },
        );

        // Project requests is ONE row; adding the two areas would claim 11.
        expect(counts, {'project-requests': 7});
        expect(calls, unorderedEquals([AppAreas.admin, AppAreas.sales]));
      },
    );

    test('a failed loader leaves its badge absent, not a fake zero', () async {
      final counts = await MergedSidebar.loadMergedBadges(
        const ['pos', 'inventory'],
        loaders: {
          AppAreas.pos: () async => throw StateError('server down'),
          AppAreas.inventory: () async => 0,
        },
      );

      expect(counts, isEmpty);
    });

    test('each count lands on its own area destination id', () async {
      final counts = await MergedSidebar.loadMergedBadges(
        AppAreas.codes,
        loaders: {
          AppAreas.pos: () async => 3,
          AppAreas.inventory: () async => 5,
          AppAreas.sales: () async => 9,
          AppAreas.admin: () async => 2,
        },
      );

      expect(counts, {
        'pos.held': 3,
        'inventory.low-stock': 5,
        // Admin is the wider owner of the shared row, so its answer stands.
        'project-requests': 2,
      });
    });
  });

  group('a page in any shell highlights its one merged row', () {
    testWidgets('Cashier + Store Manager, opened from the till', (
      tester,
    ) async {
      await _pump(
        tester,
        await _auth([_sales, _pos]),
        _cashierShell(selected: 4),
      );

      expect(_tile(tester, 'Held transactions').selected, isTrue);
      expect(find.text('TILL'), findsOneWidget);
      expect(find.text('SALES'), findsOneWidget);
      expect(_drawnRows(tester).skip(1).take(2), [
        'New transaction',
        'Transaction history',
      ], reason: 'Till keeps its own order above Sales, below the landing row');
    });

    testWidgets('Stock + Store Manager, opened from Sales', (tester) async {
      await _pump(
        tester,
        await _auth([_inventory, _sales]),
        _salesShell(selected: 9),
      );

      expect(find.text('STOCK'), findsOneWidget);
      expect(find.text('SALES'), findsOneWidget);
      expect(
        find.text('Payables'),
        findsOneWidget,
        reason: 'the shared page is drawn once, not once per area',
      );
      expect(_tile(tester, 'Payables').selected, isTrue);
    });

    testWidgets('Admin + Cashier, opened from the till', (tester) async {
      await _pump(
        tester,
        await _auth([_admin, _pos]),
        _cashierShell(selected: 1),
      );

      expect(_tile(tester, 'Transaction history').selected, isTrue);
      expect(find.text('ADMIN'), findsOneWidget);
      expect(_tile(tester, 'User management').selected, isFalse);
    });

    testWidgets('Admin + Cashier, opened from Admin', (tester) async {
      await _pump(
        tester,
        await _auth([_admin, _pos]),
        _adminShell(selected: AdminSkeletonLayout.projectRequestsIndex),
        size: _tall,
      );

      expect(_tile(tester, 'Project requests').selected, isTrue);
      expect(find.text('ADMIN'), findsOneWidget);
      expect(find.text('TILL'), findsOneWidget);
    });

    testWidgets('a lower-area shared page highlights the widest merged row', (
      tester,
    ) async {
      // The Store Manager's own payables page (index 9), with Admin also held:
      // the merged row is the ADMIN one, and it is the row that lights up.
      await _pump(
        tester,
        await _auth([_admin, _sales]),
        _salesShell(selected: 9),
        size: _tall,
      );

      expect(find.text('Payables'), findsOneWidget);
      expect(_tile(tester, 'Payables').selected, isTrue);
      expect(
        _tile(tester, 'User management').selected,
        isFalse,
        reason: 'the Admin row for the same page is the one drawn',
      );
    });
  });

  group('tapping a merged row', () {
    testWidgets('opens the widest area route of a shared page', (tester) async {
      final router = GoRouter(
        initialLocation: AppRoutes.salesPayables,
        routes: [
          GoRoute(
            path: AppRoutes.salesPayables,
            builder: (context, state) => _salesShell(selected: 9),
          ),
          GoRoute(
            path: AppRoutes.adminPayables,
            builder: (context, state) => const Scaffold(body: Text('ADMIN')),
          ),
          GoRoute(
            path: AppRoutes.combinedDashboard,
            builder: (context, state) => const Scaffold(body: Text('COMBINED')),
          ),
        ],
      );
      addTearDown(router.dispose);
      tester.view.physicalSize = _tall;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewmodel>.value(
          value: await _auth([_admin, _sales]),
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Payables'));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.adminPayables,
        reason: 'the merged row links to the widest area route',
      );
      expect(find.text('ADMIN'), findsOneWidget);
    });

    testWidgets('the landing row opens the combined dashboard', (tester) async {
      final router = GoRouter(
        initialLocation: AppRoutes.salesPayables,
        routes: [
          GoRoute(
            path: AppRoutes.salesPayables,
            builder: (context, state) => _salesShell(selected: 9),
          ),
          GoRoute(
            path: AppRoutes.combinedDashboard,
            builder: (context, state) => _combinedPage(),
          ),
        ],
      );
      addTearDown(router.dispose);
      tester.view.physicalSize = _tall;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewmodel>.value(
          value: await _auth([_admin, _sales]),
          child: MaterialApp.router(
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Needs you'));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.path,
        AppRoutes.combinedDashboard,
        reason: 'every merged page reaches the one landing page',
      );
    });
  });

  group('the merged badges on screen', () {
    testWidgets('a page count wins, and clearing it clears the badge', (
      tester,
    ) async {
      final auth = await _auth([_inventory, _sales]);
      await _pump(
        tester,
        auth,
        _inventoryShell(selected: 5, markers: const {5: 2}),
        size: _tall,
      );
      expect(_markedRows(tester), ['Low stock']);

      // The page resolved its last alert and reports zero: still on that page,
      // the badge has to go.
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewmodel>.value(
          value: auth,
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: _inventoryShell(selected: 5, markers: const {5: 0}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(_markedRows(tester), isEmpty);
    });

    testWidgets('a failed read draws no badge and no zero', (tester) async {
      await _pump(tester, await _auth([_inventory, _sales]), _salesShell());

      // No server in a widget test: every merged loader fails, and a failure is
      // a blank badge, never a "0" claiming the queue is empty.
      expect(_markedRows(tester), isEmpty);
      expect(find.text('0'), findsNothing);
    });
  });

  group('widths and the area switcher', () {
    testWidgets('1440: one grouped list with a heading per area', (
      tester,
    ) async {
      await _pump(tester, await _auth([_sales, _pos]), _cashierShell());

      expect(find.text('TILL'), findsOneWidget);
      expect(find.text('SALES'), findsOneWidget);
      expect(find.text('SELLING'), findsNothing, reason: 'area headings only');
    });

    testWidgets('1100: the rail keeps every row and moves labels to tooltips', (
      tester,
    ) async {
      await _pump(
        tester,
        await _auth([_sales, _pos]),
        _cashierShell(),
        size: _tallRail,
      );

      expect(find.text('SALES'), findsNothing);
      expect(find.byTooltip('Held transactions'), findsOneWidget);
      expect(find.byTooltip('Payables'), findsOneWidget);
    });

    testWidgets('760: the drawer holds the same merged list', (tester) async {
      await _pump(
        tester,
        await _auth([_sales, _pos]),
        _cashierShell(),
        size: const Size(760, 900),
      );
      expect(find.text('Held transactions'), findsNothing);

      await tester.tap(find.byTooltip('Open menu'));
      await tester.pumpAndSettle();

      expect(find.text('TILL'), findsOneWidget);
      expect(find.text('SALES'), findsOneWidget);
      expect(find.text('Held transactions'), findsOneWidget);
    });

    testWidgets('the switcher is retired for a merged account only', (
      tester,
    ) async {
      await _pump(tester, await _auth([_sales, _pos]), _cashierShell());
      expect(find.byType(AreaSwitcherMenu), findsNothing);
      expect(find.byTooltip('Switch area'), findsNothing);

      // A single-area account is untouched: the widget is still built (its code
      // is kept, not deleted) and simply has nothing to offer.
      await _pump(tester, await _auth([_pos]), _cashierShell());
      expect(find.byType(AreaSwitcherMenu), findsOneWidget);
      expect(find.byTooltip('Switch area'), findsNothing);
    });
  });
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(this.account) : super(_UnusedAuthService());

  final User account;

  @override
  Future<User?> restoreSession() async => account;

  @override
  Future<User> login(String identifier, String password) async => account;

  @override
  Future<void> logout() async {}
}

class _UnusedAuthService extends AuthService {
  @override
  Future<AuthSession> login(String identifier, String password) async {
    throw const AuthException('not used in these tests');
  }

  @override
  Future<void> logout() async {}
}
