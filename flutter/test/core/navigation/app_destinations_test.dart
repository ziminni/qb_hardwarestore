// Phase 2 F1 (decision 24): the four menus are DERIVED from one registry now, so
// the risk moved. A route adapter can no longer drift from a sidebar by hand, but
// the registry itself can still hold the wrong menu: a reordered row, a renamed
// label, a swapped icon, a lost group heading, a badge on the wrong row, a page
// that silently became "shared" with a different page.
//
// WHAT THIS PINS: every row of all four menus by its USE-VISIBLE values (label,
// icon, route, the heading it starts, whether it carries a badge) and its flat
// index, which is its position. The expectations are literal on purpose: a
// registry that "derives" the wrong menu still fails here.
//
// WHAT IT DOES NOT PROVE: that the shells render these lists (that is
// `sidebar_pattern_test.dart`, unchanged) or that the 12 sidebar goldens still look
// the same (they do not regenerate).

import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// One expected menu row: [group] is the heading this row STARTS (null when it
/// continues the heading above), [badge] is whether the shell's marker loader
/// targets it.
class _Row {
  const _Row(
    this.label,
    this.icon,
    this.route, [
    this.group,
    this.badge = false,
  ]);

  final String label;
  final IconData icon;
  final String route;
  final String? group;
  final bool badge;
}

const _tillMenu = <_Row>[
  _Row(
    'New transaction',
    Icons.point_of_sale_outlined,
    AppRoutes.posDashboard,
    'Selling',
  ),
  _Row(
    'Transaction history',
    Icons.receipt_long_outlined,
    AppRoutes.posHistory,
  ),
  _Row(
    'Release materials',
    Icons.inventory_2_outlined,
    AppRoutes.posRelease,
    'Customers and projects',
  ),
  _Row('Record payment', Icons.payments_outlined, AppRoutes.posReceivables),
  _Row(
    'Held transactions',
    Icons.pause_circle_outline,
    AppRoutes.posHeld,
    'Till',
    true,
  ),
  _Row('Shifts', Icons.access_time, AppRoutes.posShifts),
  _Row('Returns', Icons.assignment_return_outlined, AppRoutes.posReturns),
];

const _storeManagerMenu = <_Row>[
  _Row(
    'Dashboard',
    Icons.dashboard_outlined,
    AppRoutes.salesDashboard,
    'Overview',
  ),
  _Row(
    'Transactions',
    Icons.receipt_long_outlined,
    AppRoutes.salesTransactions,
    'Selling',
  ),
  _Row('Quotations', Icons.request_quote_outlined, AppRoutes.salesQuotations),
  _Row('Sales orders', Icons.assignment_outlined, AppRoutes.salesOrders),
  _Row(
    'Receivables',
    Icons.account_balance_wallet_outlined,
    AppRoutes.salesReceivables,
    'Customers',
  ),
  _Row(
    'Returns & refunds',
    Icons.assignment_return_outlined,
    AppRoutes.salesReturns,
    'After Sales',
  ),
  _Row('Reports', Icons.bar_chart_outlined, AppRoutes.salesReports, 'Insights'),
  _Row(
    'Staff',
    Icons.manage_accounts_outlined,
    AppRoutes.salesStaff,
    'Management',
  ),
  _Row(
    'Project requests',
    Icons.fact_check_outlined,
    AppRoutes.salesProjectRequests,
    'Projects',
    true,
  ),
  _Row(
    'Payables',
    Icons.account_balance_wallet_outlined,
    AppRoutes.salesPayables,
    'Payables',
  ),
  _Row(
    'Deliveries',
    Icons.local_shipping_outlined,
    AppRoutes.salesDeliveries,
    'Deliveries',
  ),
  _Row(
    'Transfers',
    Icons.swap_horiz_rounded,
    AppRoutes.salesTransfers,
    'Transfers',
  ),
];

const _stockManagerMenu = <_Row>[
  _Row(
    'Dashboard',
    Icons.dashboard_outlined,
    AppRoutes.inventoryDashboard,
    'Overview',
  ),
  _Row(
    'Products',
    Icons.inventory_2_outlined,
    AppRoutes.inventoryProducts,
    'Inventory',
  ),
  _Row('Categories', Icons.category_outlined, AppRoutes.inventoryCategories),
  _Row('Stock', Icons.warehouse_outlined, AppRoutes.inventoryStock),
  _Row(
    'Stock adjustments',
    Icons.swap_vert_rounded,
    AppRoutes.inventoryStockMovements,
  ),
  _Row(
    'Low stock',
    Icons.warning_amber_rounded,
    AppRoutes.inventoryLowStock,
    null,
    true,
  ),
  _Row(
    'Purchases',
    Icons.shopping_bag_outlined,
    AppRoutes.inventoryPurchases,
    'Purchasing',
  ),
  _Row(
    'Suppliers',
    Icons.local_shipping_outlined,
    AppRoutes.inventorySuppliers,
  ),
  _Row('Receiving', Icons.move_to_inbox_outlined, AppRoutes.inventoryReceiving),
  _Row(
    'Sales',
    Icons.shopping_cart_outlined,
    AppRoutes.inventorySales,
    'Sales',
  ),
  _Row('Returns', Icons.undo_rounded, AppRoutes.inventoryReturns),
  _Row('Reports', Icons.bar_chart_rounded, AppRoutes.inventoryReports),
  _Row('Settings', Icons.settings_outlined, AppRoutes.inventorySettings),
  _Row(
    'Payables',
    Icons.account_balance_wallet_outlined,
    AppRoutes.inventoryPayables,
    'Payables',
  ),
  _Row(
    'Deliveries',
    Icons.local_shipping_outlined,
    AppRoutes.inventoryDeliveries,
    'Deliveries',
  ),
  _Row(
    'Transfers',
    Icons.swap_horiz_rounded,
    AppRoutes.inventoryTransfers,
    'Transfers',
  ),
];

const _adminMenu = <_Row>[
  _Row(
    'Overview',
    Icons.dashboard_outlined,
    AppRoutes.adminDashboard,
    'Overview',
  ),
  _Row(
    'User management',
    Icons.manage_accounts_outlined,
    AppRoutes.adminUserManagement,
    'People',
  ),
  _Row(
    'Inventory',
    Icons.inventory_2_outlined,
    AppRoutes.adminInventory,
    'Operations',
  ),
  _Row('Sales & POS', Icons.point_of_sale_outlined, AppRoutes.adminSales),
  _Row('Reports', Icons.bar_chart_rounded, AppRoutes.adminReports, 'Insights'),
  _Row('Audit logs', Icons.history_rounded, AppRoutes.adminAuditLogs, 'System'),
  _Row('Settings', Icons.settings_outlined, AppRoutes.adminSettings),
  _Row(
    'Project requests',
    Icons.fact_check_outlined,
    AppRoutes.adminProjectRequests,
    'Projects',
    true,
  ),
  _Row(
    'Payables',
    Icons.account_balance_wallet_outlined,
    AppRoutes.adminPayables,
    'Payables',
  ),
  _Row(
    'Deliveries',
    Icons.local_shipping_outlined,
    AppRoutes.adminDeliveries,
    'Deliveries',
  ),
  _Row(
    'Storage locations',
    Icons.warehouse_outlined,
    AppRoutes.adminStorageLocations,
    'Locations',
  ),
  _Row(
    'Transfers',
    Icons.swap_horiz_rounded,
    AppRoutes.adminTransfers,
    'Transfers',
  ),
];

void _expectMenu(String area, List<_Row> expected) {
  final rows = AppDestinations.forArea(area);
  expect(
    rows,
    hasLength(expected.length),
    reason: '$area sidebar row count changed; every row below is pinned',
  );
  for (var index = 0; index < expected.length; index++) {
    final want = expected[index];
    final got = rows[index];
    expect(got.label, want.label, reason: '$area row $index label');
    expect(got.icon, want.icon, reason: '$area row $index icon');
    expect(got.route, want.route, reason: '$area row $index route');
    expect(
      got.group,
      want.group,
      reason:
          '$area row $index starts the group "${want.group}"; the heading is how '
          'the section starts without renumbering a single destination',
    );
    expect(
      got.badge,
      want.badge,
      reason: '$area row $index badge: the shell marker must land on this row',
    );
    expect(
      got.area,
      area,
      reason: '$area row $index is tagged with another area',
    );
  }
  expect(
    rows.first.group,
    isNotNull,
    reason:
        'the first row must start the first group, or it renders headingless',
  );
}

void main() {
  test('the Till menu is the cashier menu, row by row', () {
    _expectMenu(AppAreas.pos, _tillMenu);
  });

  test('the Sales menu is the store manager menu, row by row', () {
    _expectMenu(AppAreas.sales, _storeManagerMenu);
  });

  test('the Stock menu is the stock manager menu, row by row', () {
    _expectMenu(AppAreas.inventory, _stockManagerMenu);
  });

  test('the Admin menu is the admin menu, row by row', () {
    _expectMenu(AppAreas.admin, _adminMenu);
  });

  test('47 menu rows are 38 pages: only the locked set is shared', () {
    // Without the counts, an empty or duplicated registry would make every
    // per-area check above pass against nothing.
    expect(
      AppDestinations.all,
      hasLength(47),
      reason: '4 menus: Till 7, Sales 12, Stock 16, Admin 12',
    );
    expect(
      AppDestinations.all.map((row) => row.id).toSet(),
      hasLength(38),
      reason:
          'Payables, Deliveries, Reports, Project requests, Staff and Transfers '
          'appear in more than one menu; every other row is one page',
    );
    expect(
      AppDestinations.all
          .where((row) => row.sharedKey != null)
          .map((row) => row.id)
          .toSet(),
      AppDestinations.sharedIds,
      reason:
          'a page is shared only when decision 24 locked it; a new shared key '
          'would de-duplicate two different pages in the merged sidebar',
    );
    for (final row in AppDestinations.all) {
      if (row.sharedKey == null) continue;
      expect(
        row.sharedKey,
        row.id,
        reason: '${row.id} must share under its own id, never under a label',
      );
    }
  });

  test(
    'Stock Reports is a different page from the Admin and Sales Reports',
    () {
      final stockReports = AppDestinations.forArea(
        AppAreas.inventory,
      ).firstWhere((row) => row.id == 'inventory.reports');
      expect(stockReports.label, 'Reports');
      expect(stockReports.sharedKey, isNull);
      expect(stockReports.route, AppRoutes.inventoryReports);
      final others = [
        ...AppDestinations.forArea(AppAreas.admin),
        ...AppDestinations.forArea(AppAreas.sales),
      ].where((row) => row.id == 'reports');
      expect(others, hasLength(2));
      for (final row in others) {
        expect(row.sharedKey, 'reports');
      }
    },
  );

  test('each group heading sits at the index its area already had', () {
    const expected = {
      AppAreas.pos: [
        ('Selling', 0),
        ('Customers and projects', 2),
        ('Till', 4),
      ],
      AppAreas.sales: [
        ('Overview', 0),
        ('Selling', 1),
        ('Customers', 4),
        ('After Sales', 5),
        ('Insights', 6),
        ('Management', 7),
        ('Projects', 8),
        ('Payables', 9),
        ('Deliveries', 10),
        ('Transfers', 11),
      ],
      AppAreas.inventory: [
        ('Overview', 0),
        ('Inventory', 1),
        ('Purchasing', 6),
        ('Sales', 9),
        ('Payables', 13),
        ('Deliveries', 14),
        ('Transfers', 15),
      ],
      AppAreas.admin: [
        ('Overview', 0),
        ('People', 1),
        ('Operations', 2),
        ('Insights', 4),
        ('System', 5),
        ('Projects', 7),
        ('Payables', 8),
        ('Deliveries', 9),
        ('Locations', 10),
        ('Transfers', 11),
      ],
    };
    for (final area in AppAreas.codes) {
      expect(
        AppDestinations.groupsFor(area),
        expected[area],
        reason: '$area headings moved; a heading is a group START index',
      );
    }
  });

  test('the sections the sidebar renders come from those rows', () {
    // The slicing is what actually draws the rows: a heading list the sections do
    // not use would prove nothing about the menu.
    for (final area in AppAreas.codes) {
      final sections = AppDestinations.sectionsFor(area);
      final rows = AppDestinations.forArea(area);
      final flat = [for (final section in sections) ...section.destinations];
      expect(
        flat.map((destination) => destination.label).toList(),
        rows.map((row) => row.label).toList(),
      );
      expect(
        flat.map((destination) => destination.icon).toList(),
        rows.map((row) => row.icon).toList(),
      );
      expect(
        sections.map((section) => section.label).toList(),
        AppDestinations.groupsFor(area).map((group) => group.$1).toList(),
        reason: '$area section headings must be the registry group headings',
      );
    }
  });

  test(
    'the route adapters reach a route at every flat index and none past it',
    () {
      for (final area in AppAreas.codes) {
        final rows = AppDestinations.forArea(area);
        for (var index = 0; index < rows.length; index++) {
          expect(AppDestinations.routeAt(area, index), rows[index].route);
        }
        expect(AppDestinations.routeAt(area, rows.length), isNull);
        expect(AppDestinations.routeAt(area, -1), isNull);
      }
    },
  );

  test('the shells draw the registry menu, not a private copy', () {
    // Production consumption, pinned: each shell's sections are the registry's
    // sections for its area. A shell that kept its own literal list would fail
    // here even while every row above is correct.
    expect(
      SalesSkeletonLayout.navigationSections
          .map((section) => section.label)
          .toList(),
      AppDestinations.sectionsFor(AppAreas.sales).map((s) => s.label).toList(),
    );
    expect(
      SalesSkeletonLayout.navigationSections
          .expand((section) => section.destinations)
          .map((destination) => destination.label)
          .toList(),
      AppDestinations.labelsFor(AppAreas.sales),
    );
    expect(
      InventorySkeletonLayout.navigationSections
          .expand((section) => section.destinations)
          .map((destination) => destination.label)
          .toList(),
      AppDestinations.labelsFor(AppAreas.inventory),
    );
    expect(
      AdminSkeletonLayout.navigationSections
          .expand((section) => section.destinations)
          .map((destination) => destination.label)
          .toList(),
      AppDestinations.labelsFor(AppAreas.admin),
    );
    expect(DashboardShell.groups, AppDestinations.groupsFor(AppAreas.pos));
  });

  test('the shells index constants point at the registry row', () {
    // The constants are const ints (pages pass them in const marker maps), so
    // Dart cannot derive them from the registry at compile time: this is the pin
    // that keeps them from lying about where their row sits.
    expect(
      AppDestinations.indexOf(
        AppDestinations.projectRequestsId,
        AppAreas.admin,
      ),
      AdminSkeletonLayout.projectRequestsIndex,
    );
    expect(
      AppDestinations.indexOf(
        AppDestinations.projectRequestsId,
        AppAreas.sales,
      ),
      SalesSkeletonLayout.projectRequestsIndex,
    );
    expect(
      AppDestinations.indexOf(AppDestinations.lowStockId, AppAreas.inventory),
      InventorySkeletonLayout.lowStockIndex,
    );
    expect(
      AppDestinations.indexOf(AppDestinations.heldTransactionsId, AppAreas.pos),
      DashboardShell.heldTransactionsIndex,
    );
  });
}
