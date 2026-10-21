// Stocker-workflow phases 1-3: three sidebar destinations clicked into nothing.
//
// Returns / Reports / Settings existed as `SharedSidebarDestination`s but had no
// route constant, and `navigateInventory`'s switch fell through to null - the
// tab highlighted on click and then the app stayed put. Separately, `Receiving`
// claimed index 9, which the sidebar renders as "Returns", so the Returns tab
// opened the Receiving screen.
//
// WHY THIS READS SOURCE FOR THE ORDER: the invariant is "the index a page
// declares is its OWN destination in ITS OWN sidebar". The navigation map and
// the sidebar list are two separate literals, so only comparing them can catch
// a renumbering. `flutter analyze` cannot: 9 is as valid an int as 10.
//
// The second half PROVES the wiring by actually navigating: a real GoRouter,
// a real tap, and the target route's own page text on screen.

import 'dart:io';

import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _sidebarFile = 'lib/core/layout/inventory_skeleton_layout.dart';
const _navFile = 'lib/features/inventory/widgets/inventory_navigation.dart';

/// Destination labels in the order the stocker sidebar renders them.
List<String> _sidebarLabels() =>
    RegExp(r"SharedSidebarDestination\(\s*label: '([^']+)'")
        .allMatches(File(_sidebarFile).readAsStringSync())
        .map((m) => m.group(1)!)
        .toList();

/// `Returns` -> `inventoryReturns`, `Stock movements` -> `inventoryStockMovements`.
String _routeForLabel(String label) {
  final words = label.split(' ');
  final camel = [
    words.first,
    for (final word in words.skip(1)) word[0].toUpperCase() + word.substring(1),
  ].join();
  return 'inventory${camel[0].toUpperCase()}${camel.substring(1)}';
}

/// The `N => AppRoutes.x` map as an index-ordered list of route names.
List<String> _navOrder() {
  final pairs =
      RegExp(r'(\d+) => AppRoutes\.(\w+),')
          .allMatches(File(_navFile).readAsStringSync())
          .map((m) => MapEntry(int.parse(m.group(1)!), m.group(2)!))
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
  return pairs.map((pair) => pair.value).toList();
}

const _inventoryPaths = <String>[
  AppRoutes.inventoryDashboard,
  AppRoutes.inventoryProducts,
  AppRoutes.inventoryCategories,
  AppRoutes.inventoryStock,
  AppRoutes.inventoryStockMovements,
  AppRoutes.inventoryLowStock,
  AppRoutes.inventoryPurchases,
  AppRoutes.inventorySuppliers,
  AppRoutes.inventoryReceiving,
  AppRoutes.inventorySales,
  AppRoutes.inventoryReturns,
  AppRoutes.inventoryReports,
  AppRoutes.inventorySettings,
];

Widget _probeApp() {
  final router = GoRouter(
    initialLocation: '/probe',
    routes: [
      GoRoute(
        path: '/probe',
        builder: (context, state) => Scaffold(
          body: Wrap(
            children: [
              for (var index = 0; index < _inventoryPaths.length; index++)
                ElevatedButton(
                  onPressed: () => navigateInventory(context, index),
                  child: Text('nav $index'),
                ),
              ElevatedButton(
                onPressed: () => navigateInventory(context, 99),
                child: const Text('nav 99'),
              ),
            ],
          ),
        ),
      ),
      for (final path in _inventoryPaths)
        GoRoute(path: path, builder: (_, _) => Text('ARRIVED $path')),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  test('the parsers find the sidebar and the navigation map', () {
    // Guard against vacuous passes: an empty parse makes every comparison
    // below trivially true.
    expect(_sidebarLabels().length, 13);
    expect(_navOrder().length, 13);
    expect(_sidebarLabels().first, 'Dashboard');
    expect(_sidebarLabels().last, 'Settings');
  });

  test('every sidebar destination has its own route at its own index', () {
    final expected = _sidebarLabels().map(_routeForLabel).toList();
    expect(
      _navOrder(),
      expected,
      reason:
          'navigateInventory must follow the sidebar order, or a tab opens a '
          'screen that is not the one it names',
    );
  });

  test('the three previously-dead tabs have route constants', () {
    expect(AppRoutes.inventoryReturns, '/inventory/returns');
    expect(AppRoutes.inventoryReports, '/inventory/reports');
    expect(AppRoutes.inventorySettings, '/inventory/settings');
  });

  testWidgets('every stocker sidebar index navigates to its own screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (var index = 0; index < _inventoryPaths.length; index++) {
      await tester.pumpWidget(_probeApp());
      await tester.tap(find.text('nav $index'));
      await tester.pumpAndSettle();
      expect(
        find.text('ARRIVED ${_inventoryPaths[index]}'),
        findsOneWidget,
        reason: 'sidebar index $index did not reach its screen',
      );
    }
  });

  testWidgets('an index no sidebar entry owns goes nowhere', (tester) async {
    await tester.pumpWidget(_probeApp());
    await tester.tap(find.text('nav 99'));
    await tester.pumpAndSettle();
    expect(find.text('nav 99'), findsOneWidget);
  });
}
