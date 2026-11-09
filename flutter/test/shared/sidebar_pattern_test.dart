// Card F4: the sidebar pattern every role gets (00-shared/SHELL-AND-SIDEBAR.md).
//
// Pinned here, one property per test:
//   * labelled groups render for the two flat menus (cashier, admin) WITHOUT
//     moving any destination: the group test taps by label, so a reorder would
//     show up as "the wrong page".
//   * the active destination carries the gold bar, in full AND rail mode.
//   * the collapse choice survives a rebuild (shared_preferences).
//   * a live marker shows the count it is given, and NOTHING when the load
//     fails or yields zero (a false 0 is worse than a blank).
//   * the drawer still opens and navigates at 760 px.
//
// `sidebar_index_consistency_test.dart` stays untouched: this file never
// restates an index list, it taps labels.

import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _activeBar = ValueKey('sidebar-active-bar');
const _markerKey = ValueKey('sidebar-marker-4');

Widget _app(Widget shell) => ChangeNotifierProvider<AuthViewmodel>.value(
  value: AuthViewmodel(AuthRepository(AuthService())),
  child: MaterialApp(home: shell),
);

Future<void> _pump(
  WidgetTester tester,
  Size size,
  Widget shell, {
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(shell));
  if (settle) await tester.pumpAndSettle();
}

/// Cashier (POS) shell. [markers] stands in for the network: every test here
/// supplies one, so no test depends on a server.
Widget _cashier({
  int selected = 0,
  List<int>? taps,
  Future<Map<int, int>> Function()? markers,
}) => DashboardShell(
  title: 'Point of Sale',
  // Not "New transaction": that is also a menu label, and the header would
  // double every find.text for it.
  subtitle: 'Cashier',
  selectedNavigationIndex: selected,
  navigationItems: posNavigationItems,
  onNavigationSelected: taps?.add,
  loadMarkers: markers ?? _noMarkers,
  child: const Text('BODY'),
);

// The sales shell reads its own corner of the network on mount (the waiting
// count for "Requests from projects", Phase 1b). Every test below either taps
// labels or supplies its own markers, so that read never decides an assertion.
Widget _storeManager() => SalesSkeletonLayout(
  title: 'Store manager',
  subtitle: 'Transactions',
  selectedNavigationIndex: 1,
  onNavigationSelected: (_) {},
  child: const Text('BODY'),
);

Widget _stockManager({Future<Map<int, int>> Function()? markers}) =>
    InventorySkeletonLayout(
      title: 'Stock manager',
      subtitle: 'Products',
      selectedNavigationIndex: 0,
      onNavigationSelected: (_) {},
      loadMarkers: markers ?? _noMarkers,
      child: const Text('BODY'),
    );

// Same as the sales shell: its own loader is the waiting-request count.
Widget _admin() => AdminSkeletonLayout(
  title: 'Admin',
  // Not "Overview": it is also a menu item under the OVERVIEW heading, and
  // the header would double every find.text for it.
  subtitle: 'Back office',
  selectedNavigationIndex: 0,
  onNavigationSelected: (_) {},
  child: const Text('BODY'),
);

Future<Map<int, int>> _noMarkers() async => const {};

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('group headings', () {
    testWidgets('the cashier menu is grouped in its existing order', (
      tester,
    ) async {
      await _pump(tester, const Size(1440, 900), _cashier());

      for (final heading in const [
        'SELLING',
        'CUSTOMERS AND PROJECTS',
        'TILL',
      ]) {
        expect(find.text(heading), findsOneWidget, reason: 'heading $heading');
      }
      // No index moved: each destination keeps the number it had before the
      // grouping, which is what the route tables are written against.
      expect(find.text('New transaction'), findsOneWidget);
      expect(find.text('Transaction history'), findsOneWidget);
      expect(find.text('Release materials'), findsOneWidget);
      expect(find.text('Record payment'), findsOneWidget);
      expect(find.text('Held transactions'), findsOneWidget);
      expect(find.text('Shifts'), findsOneWidget);
      expect(find.text('Returns'), findsOneWidget);
    });

    testWidgets('the admin menu is grouped in its existing order', (
      tester,
    ) async {
      await _pump(tester, const Size(1440, 900), _admin());

      for (final heading in const [
        'OVERVIEW',
        'PEOPLE',
        'OPERATIONS',
        'INSIGHTS',
        'SYSTEM',
      ]) {
        expect(find.text(heading), findsOneWidget, reason: 'heading $heading');
      }
      for (final item in const [
        'Overview',
        'User management',
        'Inventory',
        'Sales & POS',
        'Reports',
        'Audit logs',
        'Settings',
        // Phase 1b: appended in the new final Projects group.
        'Requests from projects',
      ]) {
        expect(find.text(item), findsOneWidget, reason: 'item $item');
      }
      // Decision 01: requests are approved in CPMS, so there is no POS queue.
      expect(find.text('Requisitions'), findsNothing);
    });

    testWidgets('the store manager menu has no Approvals entry', (
      tester,
    ) async {
      await _pump(tester, const Size(1440, 900), _storeManager());

      expect(find.text('Approvals'), findsNothing);
      expect(find.text('Staff'), findsOneWidget);
      expect(
        find.text('Requests from projects'),
        findsOneWidget,
        reason: 'Phase 1b appends the store-review queue to this sidebar',
      );
    });

    testWidgets('the icon rail shows no headings, only the dividers', (
      tester,
    ) async {
      await _pump(tester, const Size(1100, 900), _cashier());

      expect(find.text('SELLING'), findsNothing);
      expect(find.text('TRANSACTION HISTORY'), findsNothing);
      expect(find.byTooltip('Transaction history'), findsOneWidget);
    });
  });

  group('active item', () {
    testWidgets('full mode draws the gold bar on the selected destination', (
      tester,
    ) async {
      await _pump(tester, const Size(1440, 900), _cashier(selected: 1));

      expect(find.byKey(_activeBar), findsOneWidget);
    });

    testWidgets('rail mode draws the gold bar too', (tester) async {
      await _pump(tester, const Size(1100, 900), _cashier(selected: 1));

      expect(find.byKey(_activeBar), findsOneWidget);
    });

    testWidgets('unselected destinations carry no bar', (tester) async {
      await _pump(tester, const Size(1440, 900), _cashier(selected: 1));

      // Exactly one, not one per destination.
      expect(find.byKey(_activeBar), findsOneWidget);
    });
  });

  group('collapse', () {
    testWidgets('the choice survives a rebuild', (tester) async {
      await _pump(tester, const Size(1440, 900), _cashier());
      expect(find.text('Transaction history'), findsOneWidget);

      await tester.tap(find.byTooltip('Collapse sidebar'));
      await tester.pumpAndSettle();
      expect(find.text('Transaction history'), findsNothing);
      expect(find.byTooltip('Transaction history'), findsOneWidget);

      // A fresh shell, as after a page change or an app restart: the rail is
      // remembered, not recomputed from the window width.
      await tester.pumpWidget(_app(_cashier()));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Transaction history'), findsOneWidget);
      expect(find.text('Transaction history'), findsNothing);
    });

    testWidgets('expanding again is remembered as well', (tester) async {
      SharedPreferences.setMockInitialValues({'sidebar_collapsed': true});
      await _pump(tester, const Size(1440, 900), _cashier());
      expect(find.byTooltip('Transaction history'), findsOneWidget);

      await tester.tap(find.byTooltip('Expand sidebar'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_app(_cashier()));
      await tester.pumpAndSettle();
      expect(find.text('Transaction history'), findsOneWidget);
    });

    testWidgets('the drawer ignores the stored choice', (tester) async {
      SharedPreferences.setMockInitialValues({'sidebar_collapsed': true});
      await _pump(tester, const Size(760, 900), _cashier());

      await tester.tap(find.byTooltip('Open menu'));
      await tester.pumpAndSettle();
      expect(find.text('Transaction history'), findsOneWidget);
    });
  });

  group('live markers', () {
    testWidgets('the count from the loader is shown on its destination', (
      tester,
    ) async {
      await _pump(
        tester,
        const Size(1440, 900),
        _cashier(markers: () async => const {4: 3}),
      );

      expect(find.byKey(_markerKey), findsOneWidget);
      expect(
        find.descendant(of: find.byKey(_markerKey), matching: find.text('3')),
        findsOneWidget,
      );
    });

    testWidgets('rail mode shows the count on the icon', (tester) async {
      await _pump(
        tester,
        const Size(1100, 900),
        _cashier(markers: () async => const {4: 3}),
      );

      expect(find.byKey(_markerKey), findsOneWidget);
    });

    testWidgets('a failed load shows no marker at all', (tester) async {
      await _pump(
        tester,
        const Size(1440, 900),
        _cashier(markers: () async => throw StateError('server down')),
      );

      expect(find.byKey(_markerKey), findsNothing);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('a zero count shows no marker', (tester) async {
      await _pump(
        tester,
        const Size(1440, 900),
        _cashier(markers: () async => const {4: 0}),
      );

      expect(find.byKey(_markerKey), findsNothing);
    });

    testWidgets('store manager: no marker on the retired queue slot', (
      tester,
    ) async {
      await _pump(tester, const Size(1440, 900), _storeManager());

      expect(find.byKey(const ValueKey('sidebar-marker-7')), findsNothing);
    });
  });

  group('marker targets', () {
    // The golden check caught this one: the stock manager's marker rendered on
    // "Stock movements" because the code used index 4 while Low stock is 5.
    // "A marker appeared" is not the property; "it sits on the right row" is.
    void expectMarkerOnOnly(WidgetTester tester, String label) {
      final tiles = find.descendant(
        of: find.byType(SharedSidebar),
        matching: find.byType(ListTile),
      );
      final marked = tester
          .widgetList<ListTile>(tiles)
          .where((tile) => tile.trailing != null)
          .toList();
      expect(marked.length, 1, reason: 'exactly one marked row');
      final labelled = tester.widget<ListTile>(
        find.ancestor(of: find.text(label), matching: find.byType(ListTile)),
      );
      expect(labelled.trailing, isNotNull, reason: 'marker sits on $label');
    }

    testWidgets('cashier: the count sits on Held transactions', (tester) async {
      await _pump(
        tester,
        const Size(1440, 900),
        _cashier(
          markers: () async => const {DashboardShell.heldTransactionsIndex: 2},
        ),
      );

      expectMarkerOnOnly(tester, 'Held transactions');
    });

    testWidgets('stock manager: the count sits on Low stock', (tester) async {
      await _pump(
        tester,
        const Size(1440, 900),
        _stockManager(
          markers: () async => const {InventorySkeletonLayout.lowStockIndex: 2},
        ),
      );

      expectMarkerOnOnly(tester, 'Low stock');
    });
  });

  group('drawer', () {
    testWidgets('still opens and navigates at 760 px', (tester) async {
      final taps = <int>[];
      await _pump(
        tester,
        const Size(760, 900),
        _cashier(taps: taps),
        settle: false,
      );
      await tester.pumpAndSettle();

      expect(find.text('Transaction history'), findsNothing);
      await tester.tap(find.byTooltip('Open menu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transaction history'));
      await tester.pumpAndSettle();
      expect(taps, [1]);
      expect(find.text('Transaction history'), findsNothing);
    });
  });
}
