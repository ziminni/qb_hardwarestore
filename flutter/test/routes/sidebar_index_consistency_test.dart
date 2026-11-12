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
      11,
      reason:
          'the sales sidebar has 11 destinations — Reports (index 6) was added by '
          'decision D-01 so the manager can reach live reports inside their own shell; '
          'Staff (7), Project requests (8) and Payables (9) were APPENDED the same '
          'way, and Deliveries (10) by Phase 5 F3 (decision 18). '
          'Approvals is gone (decision 01: CPMS approves)',
    );
    expect(
      inventoryOrder.length,
      15,
      reason:
          'the inventory sidebar has 15 destinations — Phase 5 F2 APPENDED '
          'Payables at 13 and F3 APPENDED Deliveries at 14 (decision 18)',
    );
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
    expect(salesOrder[7], 'salesStaff');
    expect(
      salesOrder[9],
      'salesPayables',
      reason:
          'Phase 5 F2 APPENDED Payables at 9 (decision 18): the Store Manager '
          'records supplier payments in the sales shell',
    );
    expect(
      salesOrder[10],
      'salesDeliveries',
      reason:
          'Phase 5 F3 APPENDED Deliveries at 10 (decision 18): the manager runs '
          'the schedule from the sales shell, and no earlier tab moved',
    );
    expect(
      salesOrder[8],
      'salesProjectRequests',
      reason:
          'Phase 1b appended the store-review queue after Staff; renumbering an '
          'earlier tab would send a manager to the wrong screen',
    );
    // Receiving must sit at 8, not 9: the sidebar's index 9 is "Returns".
    // When this was the other way round the Returns tab opened Receiving.
    expect(inventoryOrder[8], 'inventoryReceiving');
    expect(inventoryOrder[9], 'inventorySales');
    expect(inventoryOrder[10], 'inventoryReturns');
    expect(inventoryOrder[11], 'inventoryReports');
    expect(inventoryOrder[12], 'inventorySettings');
    expect(
      inventoryOrder[13],
      'inventoryPayables',
      reason:
          'Phase 5 F2 APPENDED Payables at 13, so the Stock Manager reads what '
          'the shop owes without any earlier tab moving',
    );
    expect(
      inventoryOrder[14],
      'inventoryDeliveries',
      reason:
          'Phase 5 F3 APPENDED Deliveries at 14 (decision 18): the Stock Manager '
          'runs the schedule, and every earlier tab keeps its number',
    );
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

  // The admin sidebar is not covered by the loop above: its menu lives in a
  // private list of tuples in the layout, and one page (user management)
  // declares TWO indexes because it also renders in the sales shell. So the
  // order is restated here on purpose, the same way `_salesPaths` restates the
  // sales contract, and each page must declare the index its own entry sits at.
  //
  // Removing one destination silently renumbers the ones after it. The admin
  // menu lost Requisitions (decision 01) and three pages kept their old
  // numbers, which the regenerated a5-requisitions golden showed as the WRONG
  // row highlighted.
  group('the admin pages highlight their own entry', () {
    const adminOrder = [
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
    ];

    const expected = {
      'dashboard/views/admin_dashboard.dart': 'Overview',
      'admin/views/admin_user_management_page.dart': 'User management',
      'admin/views/inventory_monitoring_page.dart': 'Inventory',
      'admin/views/sales_monitoring_page.dart': 'Sales & POS',
      'admin/views/reports_page.dart': 'Reports',
      'admin/views/audit_logs_page.dart': 'Audit logs',
      'admin/views/settings_page.dart': 'Settings',
      'payables/views/payables_page.dart': 'Payables',
      'deliveries/views/deliveries_page.dart': 'Deliveries',
      'admin/views/storage_locations_page.dart': 'Storage locations',
    };

    test('the restated menu really is the layout\'s menu', () {
      // Without this the map above could name a destination the sidebar does
      // not have, and every index check below would pass against nothing.
      // A long label wraps onto its own line, so the tuple's brace and its
      // label are allowed to sit apart.
      final layout = _read('lib/core/layout/admin_skeleton_layout.dart');
      final items = RegExp(
        r"\(\s*\'(\w[^\']*)\',\s*Icons",
      ).allMatches(layout).map((m) => m.group(1)!).toList();
      expect(items, adminOrder);
    });

    for (final entry in expected.entries) {
      test('${entry.key} is ${entry.value}', () {
        final source = _read('lib/features/${entry.key}');
        final declared = RegExp(
          r'selectedNavigationIndex:\s*(\d+)',
        ).allMatches(source).map((m) => int.parse(m.group(1)!)).toList();
        expect(declared, isNotEmpty, reason: 'no index declared at all');
        expect(
          declared,
          contains(adminOrder.indexOf(entry.value)),
          reason:
              '${entry.key} declares $declared, but ${entry.value} sits at '
              '${adminOrder.indexOf(entry.value)} in the admin sidebar',
        );
      });
    }
  });
}
