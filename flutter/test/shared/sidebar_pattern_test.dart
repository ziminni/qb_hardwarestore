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

import 'dart:io';

import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _activeBar = ValueKey('sidebar-active-bar');
const _markerKey = ValueKey('sidebar-marker-4');

Widget _app(Widget shell, {ThemeData? theme}) =>
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(theme: theme, home: shell),
    );

Future<void> _pump(
  WidgetTester tester,
  Size size,
  Widget shell, {
  bool settle = true,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(shell, theme: theme));
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
// count for "Project requests", Phase 1b). Every test below either taps
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
  setUp(
    () => SharedPreferences.setMockInitialValues({'sidebar_collapsed': false}),
  );

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

    testWidgets('the admin menu keeps only the Admin\'s own jobs', (
      tester,
    ) async {
      await _pump(tester, const Size(1440, 1400), _admin());

      // Owner 2026-11-18: the Admin sees everything and acts on nothing.
      // Settings is pinned at the very bottom of every role's sidebar, so its
      // standalone Configuration heading is omitted from the main list.
      const headings = ['OVERVIEW', 'PEOPLE', 'MONITORING'];
      for (final heading in headings) {
        expect(find.text(heading), findsOneWidget, reason: 'heading $heading');
      }
      final tops = [
        for (final heading in headings)
          tester.getTopLeft(find.text(heading)).dy,
      ];
      expect(tops, orderedEquals([...tops]..sort()));
      for (final item in const [
        'Dashboard',
        'User management',
        'Settings',
        'Audit logs',
        'Backup & restore',
        'Security',
      ]) {
        expect(find.text(item), findsOneWidget, reason: 'item $item');
      }
      for (final gone in const ['Sales & POS', 'Payables', 'Transfers']) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
      // Owner 2026-11-18: Reports and Project requests left the Admin menu.
      expect(find.text('Reports'), findsNothing);
      expect(find.text('Project requests'), findsNothing);
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
        find.text('Project requests'),
        findsOneWidget,
        reason: 'Phase 1b appends the store-review queue to this sidebar',
      );
    });

    testWidgets(
      'Settings is pinned at the very bottom of the sidebar in every role',
      (tester) async {
        final cases =
            <(String, Widget Function(ValueChanged<int>), String, int)>[
              (
                'Admin',
                (onTap) => AdminSkeletonLayout(
                  title: 'Admin',
                  subtitle: 'Back office',
                  selectedNavigationIndex: 0,
                  onNavigationSelected: onTap,
                  child: const Text('BODY'),
                ),
                'Security',
                2,
              ),
              (
                'Stock Manager',
                (onTap) => InventorySkeletonLayout(
                  title: 'Inventory',
                  subtitle: 'Stock',
                  selectedNavigationIndex: 0,
                  onNavigationSelected: onTap,
                  child: const Text('BODY'),
                ),
                'Import & export',
                11,
              ),
              (
                'Store Manager',
                (onTap) => SalesSkeletonLayout(
                  title: 'Sales',
                  subtitle: 'Store',
                  selectedNavigationIndex: 0,
                  onNavigationSelected: onTap,
                  child: const Text('BODY'),
                ),
                'Transfers',
                12,
              ),
              (
                'Cashier',
                (onTap) => DashboardShell(
                  title: 'Till',
                  subtitle: 'POS',
                  selectedNavigationIndex: 0,
                  navigationItems: posNavigationItems,
                  onNavigationSelected: onTap,
                  child: const Text('BODY'),
                ),
                'Customers',
                // 8, not 7: the OR-tagged tab was inserted at 2, so every later
                // till row moved one down with it.
                8,
              ),
            ];

        for (final (roleName, buildShell, lastMainLabel, expectedIndex)
            in cases) {
          final tapped = <int>[];
          await _pump(tester, const Size(1440, 1400), buildShell(tapped.add));

          final settingsY = tester.getTopLeft(find.text('Settings')).dy;
          final lastMainY = tester.getTopLeft(find.text(lastMainLabel)).dy;
          expect(
            settingsY,
            greaterThan(lastMainY),
            reason: '$roleName: Settings must sit below $lastMainLabel',
          );

          await tester.tap(find.text('Settings'));
          await tester.pumpAndSettle();
          expect(
            tapped,
            [expectedIndex],
            reason: '$roleName: Settings keeps its original destination index',
          );
        }
      },
    );

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

    testWidgets(
      'shows close button beside brand text only when open; clicking free space, logo, or edge opens when closed',
      (tester) async {
        await _pump(tester, const Size(1440, 900), _cashier());

        // Close button is shown beside the brand text while the sidebar is open.
        final collapseBtn = find.byKey(
          const ValueKey('sidebar-collapse-button'),
        );
        expect(collapseBtn, findsOneWidget);
        expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);

        // Clicking the close button collapses the sidebar, and the button
        // hides while collapsed.
        await tester.tap(collapseBtn);
        await tester.pumpAndSettle();
        expect(find.text('Transaction history'), findsNothing);
        expect(collapseBtn, findsNothing);
        expect(find.byIcon(Icons.chevron_left_rounded), findsNothing);
        expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

        // Clicking a non-icon / free space area inside the collapsed sidebar
        // opens the sidebar again.
        await tester.tapAt(const Offset(38, 620));
        await tester.pumpAndSettle();
        expect(find.text('Transaction history'), findsOneWidget);
        expect(collapseBtn, findsOneWidget);

        // The edge line sits on the sidebar seam with a resize-left cursor
        // while expanded, and clicking it collapses the sidebar.
        final edgeFinder = find.byKey(const ValueKey('sidebar-edge-toggle'));
        expect(edgeFinder, findsOneWidget);
        MouseRegion edgeRegion() => tester.widget<MouseRegion>(
          find
              .descendant(of: edgeFinder, matching: find.byType(MouseRegion))
              .first,
        );
        expect(edgeRegion().cursor, SystemMouseCursors.resizeLeft);

        await tester.tap(edgeFinder);
        await tester.pumpAndSettle();
        expect(find.text('Transaction history'), findsNothing);
        expect(collapseBtn, findsNothing);

        // Once collapsed, the edge line shows the extend-right cursor and
        // clicking it opens the sidebar again.
        expect(edgeRegion().cursor, SystemMouseCursors.resizeRight);
        await tester.tap(edgeFinder);
        await tester.pumpAndSettle();
        expect(find.text('Transaction history'), findsOneWidget);

        // Clicking the Queen Builders logo also collapses and re-opens it.
        final logoToggle = find.byKey(const ValueKey('sidebar-brand-toggle'));
        expect(logoToggle, findsOneWidget);
        await tester.tap(logoToggle);
        await tester.pumpAndSettle();
        expect(find.text('Transaction history'), findsNothing);

        await tester.tap(logoToggle);
        await tester.pumpAndSettle();
        expect(find.text('Transaction history'), findsOneWidget);
      },
    );

    testWidgets('defaults to collapsed when no preference is stored', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await _pump(tester, const Size(1440, 900), _cashier());

      expect(find.text('Transaction history'), findsNothing);
      expect(
        find.byKey(const ValueKey('sidebar-collapse-button')),
        findsNothing,
      );
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

  group('project requests destination', () {
    // At 1440 px the full sidebar is 260 wide, and the count badge plus the
    // selected row's 700 weight left the old label at "Requests from p…". The
    // label is now "Project requests"; the width is the property, and it only
    // means anything with the real faces loaded (the harness font is narrow).
    testWidgets('the label fits beside its count badge at 1440 px', (
      tester,
    ) async {
      // Real file reads never finish inside the test's fake clock.
      await tester.runAsync(() async {
        for (final (family, file) in const [
          ('OpenSans', 'OpenSans-Regular.ttf'),
          ('OpenSans', 'OpenSans-Bold.ttf'),
          ('Cinzel', 'Cinzel-Bold.ttf'),
        ]) {
          final bytes = await File('assets/fonts/$file').readAsBytes();
          await (FontLoader(
            family,
          )..addFont(Future.value(ByteData.view(bytes.buffer)))).load();
        }
      });

      final shells = <(String, Widget, int)>[
        // Owner 2026-11-18: the Admin menu has no badged row any more (Project
        // requests left it), so only the Store Manager's queue is checked.
        (
          'store manager',
          SalesSkeletonLayout(
            title: 'Store manager',
            subtitle: 'Transactions',
            selectedNavigationIndex: 1,
            onNavigationSelected: (_) {},
            loadMarkers: () async => const {
              SalesSkeletonLayout.projectRequestsIndex: 4,
            },
            child: const Text('BODY'),
          ),
          SalesSkeletonLayout.projectRequestsIndex,
        ),
      ];

      for (final (name, shell, index) in shells) {
        await _pump(
          tester,
          const Size(1440, 900),
          shell,
          theme: AppTheme.lightTheme,
        );
        expect(
          find.byKey(ValueKey('sidebar-marker-$index')),
          findsOneWidget,
          reason: '$name: the label must be measured WITH the count beside it',
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.text('Project requests'),
            matching: find.byType(RichText),
          ),
        );
        expect(
          paragraph.getMaxIntrinsicWidth(double.infinity),
          lessThanOrEqualTo(paragraph.size.width),
          reason: '$name sidebar truncates the "Project requests" label',
        );
      }
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
