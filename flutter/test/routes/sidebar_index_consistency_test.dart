// Task 19: `selectedNavigationIndex` had ZERO tests on any page.
//
// That is not academic. Deleting the sales customers page renumbered the INVENTORY sidebar - an
// inventory user opening Sales saw SUPLIERS... actually saw "Suppliers" highlighted - because the
// renumbering was applied by script to "the five pages after it" without checking which sidebar
// each page belonged to. No test covered the property, and `flutter analyze` cannot see it: the
// index is just an int, and 7 is as valid as 8.
//
// Phase 2 F1 moved the four menus into ONE registry (`AppDestinations`) and the route adapters read
// it too, so an index can no longer drift from a hand-kept parallel list. The property this file
// pins is unchanged, and it is now pinned against the menu PRODUCTION RENDERS: the number a page
// declares must be that page's own row in its own area's menu.
//
// WHY THIS STILL READS SOURCE FOR THE PAGE INDEXES: rendering each page needs its viewmodel
// providers, and a widget test that failed to build a provider would fail for a reason unrelated to
// the index. `selectedNavigationIndex: 7` is genuinely a source-level fact, so it is checked where
// it is written; the menu it is checked AGAINST now comes from the registry, not from a regex over
// a literal list.
//
// WHAT IT DOES NOT PROVE: that the sidebar renders, or that tapping it navigates (that is
// `inventory_returns_routing_test.dart` and `sales_reports_routing_test.dart`, which pump a real
// router). It proves the index each page declares resolves back to that page's own route.
//
// The registry reads are guarded against passing VACUOUSLY: an empty list would make every
// assertion below trivially true, which is the failure mode this project has hit four times.

import 'dart:io';

import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// `path: salesOrders` ... `_transitionPage(state, const SalesOrdersPage())` -> the route
/// constant's PATH for each page class, read from the router itself rather than restated here.
Map<String, String> _pageRoutes(String routes) {
  final pattern = RegExp(
    r'path:\s*(\w+),[\s\S]{0,220}?_transitionPage\(state,\s*const\s+(\w+)\(\)\)',
  );
  return {for (final m in pattern.allMatches(routes)) m.group(2)!: m.group(1)!};
}

/// The route path of every `AppRoutes` constant, read from the router source: `salesOrder` ->
/// `/sales/orders`. The registry stores paths, the old expectations named constants, so this keeps
/// one spelling per route.
Map<String, String> _routePaths(String routes) {
  final pattern = RegExp(r"static const String (\w+) = '([^']+)';");
  return {for (final m in pattern.allMatches(routes)) m.group(1)!: m.group(2)!};
}

void main() {
  final routes = _read('lib/routes/routes.dart');
  final pageRoutes = _pageRoutes(routes);
  final routePaths = _routePaths(routes);
  final tillOrder = AppDestinations.routesFor(AppAreas.pos);
  final salesOrder = AppDestinations.routesFor(AppAreas.sales);
  final inventoryOrder = AppDestinations.routesFor(AppAreas.inventory);
  final adminOrder = AppDestinations.labelsFor(AppAreas.admin);

  test('the parser actually finds the pages and all four menus', () {
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
      12,
      reason:
          'the sales sidebar has 12 destinations — Reports (index 6) was added by '
          'decision D-01 so the manager can reach live reports inside their own shell; '
          'Staff (7), Project requests (8) and Payables (9) were APPENDED the same '
          'way, Deliveries (10) by Phase 5 F3 (decision 18) and Transfers (11) by '
          'Phase 9 F3. Approvals is gone (decision 01: CPMS approves)',
    );
    expect(
      inventoryOrder.length,
      16,
      reason:
          'the inventory sidebar has 16 destinations — Phase 5 F2 APPENDED '
          'Payables at 13, F3 APPENDED Deliveries at 14 (decision 18) and Phase 9 '
          'F3 APPENDED Transfers at 15',
    );
    expect(
      tillOrder.length,
      7,
      reason:
          'the POS sidebar has 7 destinations — Returns (decision 05) was '
          'APPENDED at index 6, so tabs 0-5 keep their numbers',
    );
    expect(
      adminOrder.length,
      12,
      reason:
          'the admin sidebar has 12 destinations — Project requests (7), '
          'Payables (8), Deliveries (9), Storage locations (10) and Transfers (11) '
          'were all APPENDED, so 0-6 keep their numbers',
    );

    expect(salesOrder.first, AppRoutes.salesDashboard);
    expect(
      salesOrder[6],
      AppRoutes.salesReports,
      reason: 'index 6 is Reports — the tab that used to be a silent no-op',
    );
    expect(salesOrder[7], AppRoutes.salesStaff);
    expect(
      salesOrder[9],
      AppRoutes.salesPayables,
      reason:
          'Phase 5 F2 APPENDED Payables at 9 (decision 18): the Store Manager '
          'records supplier payments in the sales shell',
    );
    expect(
      salesOrder[10],
      AppRoutes.salesDeliveries,
      reason:
          'Phase 5 F3 APPENDED Deliveries at 10 (decision 18): the manager runs '
          'the schedule from the sales shell, and no earlier tab moved',
    );
    expect(
      salesOrder[8],
      AppRoutes.salesProjectRequests,
      reason:
          'Phase 1b appended the store-review queue after Staff; renumbering an '
          'earlier tab would send a manager to the wrong screen',
    );
    // Receiving must sit at 8, not 9: the sidebar's index 9 is "Returns".
    // When this was the other way round the Returns tab opened Receiving.
    expect(inventoryOrder[8], AppRoutes.inventoryReceiving);
    expect(inventoryOrder[9], AppRoutes.inventorySales);
    expect(inventoryOrder[10], AppRoutes.inventoryReturns);
    expect(inventoryOrder[11], AppRoutes.inventoryReports);
    expect(inventoryOrder[12], AppRoutes.inventorySettings);
    expect(
      inventoryOrder[13],
      AppRoutes.inventoryPayables,
      reason:
          'Phase 5 F2 APPENDED Payables at 13, so the Stock Manager reads what '
          'the shop owes without any earlier tab moving',
    );
    expect(
      inventoryOrder[14],
      AppRoutes.inventoryDeliveries,
      reason:
          'Phase 5 F3 APPENDED Deliveries at 14 (decision 18): the Stock Manager '
          'runs the schedule, and every earlier tab keeps its number',
    );
    expect(tillOrder[0], AppRoutes.posDashboard);
    expect(tillOrder[2], AppRoutes.posRelease);
    expect(tillOrder[4], AppRoutes.posHeld);
    expect(tillOrder[5], AppRoutes.posShifts);
    expect(
      tillOrder[6],
      AppRoutes.posReturns,
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
          : tillOrder;
      final sidebar = isSales
          ? 'sales'
          : isInventory
          ? 'inventory'
          : 'POS';

      test('$className points at itself in the $sidebar sidebar', () {
        final route = routePaths[pageRoutes[className]];
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

  // The admin sidebar is covered by the loop above only where a page renders in the
  // admin shell with a single index; one page (user management) declares TWO indexes
  // because it also renders in the sales shell, and the admin segments are read from
  // the registry, so the order is restated here on purpose. Each page must declare the
  // index its own entry sits at.
  //
  // Removing one destination silently renumbers the ones after it. The admin menu lost
  // Requisitions (decision 01) and three pages kept their old numbers, which the
  // regenerated a5-requisitions golden showed as the WRONG row highlighted.
  group('the admin pages highlight their own entry', () {
    const restatedAdminOrder = [
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
      'transfers/views/transfers_page.dart': 'Transfers',
    };

    test('the restated menu really is the registry\'s menu', () {
      // Without this the map above could name a destination the sidebar does
      // not have, and every index check below would pass against nothing.
      expect(adminOrder, restatedAdminOrder);
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
          contains(restatedAdminOrder.indexOf(entry.value)),
          reason:
              '${entry.key} declares $declared, but ${entry.value} sits at '
              '${restatedAdminOrder.indexOf(entry.value)} in the admin sidebar',
        );
      });
    }
  });
}
