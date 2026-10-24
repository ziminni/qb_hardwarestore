// Task 19: `selectedNavigationIndex` had ZERO tests on any page.
//
// That is not academic. Deleting the sales customers page renumbered the INVENTORY sidebar - an
// inventory user opening Sales saw SUPLIERS... actually saw "Suppliers" highlighted - because the
// renumbering was applied by script to "the five pages after it" without checking which sidebar
// each page belonged to. No test covered the property, and `flutter analyze` cannot see it: the
// index is just an int, and 7 is as valid as 8.
//
// WHY THIS READS THE SOURCE RATHER THAN PUMPING THE PAGES: rendering each page needs its
// viewmodel providers, and a widget test that failed to build a provider would fail for a reason
// unrelated to the index. The property being pinned is genuinely a source-level one - "the number
// this page declares means ITS OWN entry in ITS OWN sidebar" - so it is checked where it is
// written.
//
// WHAT IT DOES NOT PROVE: that the sidebar renders, or that tapping it navigates. It proves the
// index each page declares resolves back to that page's own route, which is exactly the
// regression that got through.
//
// The parse is guarded against passing VACUOUSLY: a regex that matched nothing would make every
// assertion below trivially true, which is the failure mode this project has hit four times.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// `path: salesOrders` ... `_transitionPage(state, const SalesOrdersPage())` -> the route
/// constant for each page class, read from the router itself rather than restated here.
Map<String, String> _pageRoutes(String routes) {
  final pattern = RegExp(
    r'path:\s*(\w+),[\s\S]{0,220}?_transitionPage\(state,\s*const\s+(\w+)\(\)\)',
  );
  return {for (final m in pattern.allMatches(routes)) m.group(2)!: m.group(1)!};
}

/// The ordered route constants of a sidebar, from its own navigation file.
List<String> _salesNavOrder(String nav) => RegExp(
  r'AppRoutes\.(\w+),',
).allMatches(nav).map((m) => m.group(1)!).toList();

/// The `N => AppRoutes.x` map, as an index -> route list.
List<String> _inventoryNavOrder(String nav) {
  final pairs =
      RegExp(r'(\d+) => AppRoutes\.(\w+),')
          .allMatches(nav)
          .map((m) => MapEntry(int.parse(m.group(1)!), m.group(2)!))
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
  return pairs.map((p) => p.value).toList();
}

void main() {
  final routes = _read('lib/routes/routes.dart');
  final pageRoutes = _pageRoutes(routes);
  final salesOrder = _salesNavOrder(
    _read('lib/features/sales/widgets/sales_navigation.dart'),
  );
  final inventoryOrder = _inventoryNavOrder(
    _read('lib/features/inventory/widgets/inventory_navigation.dart'),
  );
  final posOrder = _inventoryNavOrder(
    _read('lib/features/pos/widgets/pos_navigation.dart'),
  );

  test('the parser actually finds the pages and all three sidebars', () {
    // Without this, a regex that matched nothing makes every other assertion vacuous - the same
    // shape as the tests that could not fail earlier in this project.
    expect(
      pageRoutes.length,
      greaterThanOrEqualTo(14),
      reason:
          'every routed page should be discovered, or the checks below prove nothing',
    );
    expect(
      salesOrder.length,
      7,
      reason:
          'the sales sidebar has 7 destinations — Reports (index 6) was added by '
          'decision D-01 so the manager can reach live reports inside their own shell',
    );
    expect(inventoryOrder.length, 13);
    expect(
      posOrder.length,
      7,
      reason:
          'the POS sidebar has 7 destinations — Returns (decision 05) was '
          'APPENDED at index 6, so tabs 0-5 keep their numbers',
    );
    expect(salesOrder.first, 'salesDashboard');
    expect(
      salesOrder[6],
      'salesReports',
      reason: 'index 6 is Reports — the tab that used to be a silent no-op',
    );
    // Receiving must sit at 8, not 9: the sidebar's index 9 is "Returns".
    // When this was the other way round the Returns tab opened Receiving.
    expect(inventoryOrder[8], 'inventoryReceiving');
    expect(inventoryOrder[9], 'inventorySales');
    expect(inventoryOrder[10], 'inventoryReturns');
    expect(inventoryOrder[11], 'inventoryReports');
    expect(inventoryOrder[12], 'inventorySettings');
    expect(posOrder[0], 'posDashboard');
    expect(posOrder[2], 'posRelease');
    expect(posOrder[4], 'posHeld');
    expect(posOrder[5], 'posShifts');
    expect(
      posOrder[6],
      'posReturns',
      reason:
          'Returns is appended at 6 (decision 05). Renumbering an existing tab '
          'would send a cashier to the wrong screen — the regression this file '
          'exists for',
    );
  });

  group('every page highlights its own entry in its own sidebar', () {
    final allPages = [
      ...Directory('lib/features/sales/views').listSync().whereType<File>(),
      ...Directory('lib/features/inventory/views').listSync().whereType<File>(),
      ...Directory('lib/features/pos/views').listSync().whereType<File>(),
    ].where((f) => f.path.endsWith('.dart')).toList();

    for (final file in allPages) {
      final source = file.readAsStringSync();
      final className = RegExp(
        r'class (\w+) extends',
      ).firstMatch(source)?.group(1);
      final index = RegExp(
        r'selectedNavigationIndex:\s*(\d+)',
      ).firstMatch(source)?.group(1);
      if (className == null || index == null) continue;

      final isSales = source.contains('SalesSkeletonLayout');
      final isInventory = source.contains('InventorySkeletonLayout');
      final isPos = source.contains('posNavigationItems');
      if (!isSales && !isInventory && !isPos) continue;

      final nav = isSales
          ? salesOrder
          : isInventory
          ? inventoryOrder
          : posOrder;
      final sidebar = isSales
          ? 'sales'
          : isInventory
          ? 'inventory'
          : 'POS';

      test('$className points at itself in the $sidebar sidebar', () {
        final route = pageRoutes[className];
        if (route == null) {
          fail('$className has an index but no route in routes.dart');
        }
        final expected = nav.indexOf(route);
        expect(
          expected,
          isNot(-1),
          reason: '$className ($route) is not in the $sidebar sidebar at all',
        );
        expect(
          int.parse(index),
          expected,
          reason:
              '$className declares index $index, but $route sits at $expected in the '
              '$sidebar sidebar - so its own entry is not the one highlighted',
        );
      });
    }
  });
}
