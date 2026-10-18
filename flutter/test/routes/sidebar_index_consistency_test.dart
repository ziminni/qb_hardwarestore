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
  return {
    for (final m in pattern.allMatches(routes)) m.group(2)!: m.group(1)!,
  };
}

/// The ordered route constants of a sidebar, from its own navigation file.
List<String> _salesNavOrder(String nav) => RegExp(r'AppRoutes\.(\w+),')
    .allMatches(nav)
    .map((m) => m.group(1)!)
    .toList();

/// The `N => AppRoutes.x` map, as an index -> route list.
List<String> _inventoryNavOrder(String nav) {
  final pairs = RegExp(r'(\d+) => AppRoutes\.(\w+),')
      .allMatches(nav)
      .map((m) => MapEntry(int.parse(m.group(1)!), m.group(2)!))
      .toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return pairs.map((p) => p.value).toList();
}

void main() {
  final routes = _read('lib/routes/routes.dart');
  final pageRoutes = _pageRoutes(routes);
  final salesOrder = _salesNavOrder(_read('lib/features/sales/widgets/sales_navigation.dart'));
  final inventoryOrder =
      _inventoryNavOrder(_read('lib/features/inventory/widgets/inventory_navigation.dart'));

  test('the parser actually finds the pages and both sidebars', () {
    // Without this, a regex that matched nothing makes every other assertion vacuous - the same
    // shape as the tests that could not fail earlier in this project.
    expect(
      pageRoutes.length,
      greaterThanOrEqualTo(12),
      reason: 'every routed page should be discovered, or the checks below prove nothing',
    );
    expect(salesOrder.length, 6, reason: 'the sales sidebar has 6 destinations');
    expect(inventoryOrder.length, greaterThanOrEqualTo(10));
    expect(salesOrder.first, 'salesDashboard');
    expect(inventoryOrder[8], 'inventorySales');
    expect(inventoryOrder[9], 'inventoryReturns');
  });

  group('every page highlights its own entry in its own sidebar', () {
    final pages = Directory('lib/features/sales/views')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

    for (final file in pages) {
      final source = file.readAsStringSync();
      final className = RegExp(r'class (\w+) extends')
          .firstMatch(source)
          ?.group(1);
      final index = RegExp(r'selectedNavigationIndex:\s*(\d+)')
          .firstMatch(source)
          ?.group(1);
      if (className == null || index == null) continue;

      final isSales = source.contains('SalesSkeletonLayout');
      final isInventory = source.contains('InventorySkeletonLayout');
      if (!isSales && !isInventory) continue;

      final nav = isSales ? salesOrder : inventoryOrder;
      final sidebar = isSales ? 'sales' : 'inventory';

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
          reason: '$className declares index $index, but $route sits at $expected in the '
              '$sidebar sidebar - so its own entry is not the one highlighted',
        );
      });
    }
  });
}
