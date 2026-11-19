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
  // Owner 2026-11-18: the receipt printer is the cashier's to choose.
  _Row('Settings', Icons.settings_outlined, AppRoutes.posSettings),
  _Row('Customers', Icons.people_outline_rounded, AppRoutes.posCustomers),
];

const _storeManagerMenu = <_Row>[
  _Row(
    'Dashboard',
    Icons.dashboard_outlined,
    AppRoutes.salesDashboard,
    'Selling',
  ),
  _Row(
    'Transactions',
    Icons.receipt_long_outlined,
    AppRoutes.salesTransactions,
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
  ),
  _Row(
    'Reports',
    Icons.bar_chart_outlined,
    AppRoutes.salesReports,
    'Management',
  ),
  _Row(
    'Staff',
    Icons.manage_accounts_outlined,
    AppRoutes.salesStaff,
  ),
  _Row(
    'Project requests',
    Icons.fact_check_outlined,
    AppRoutes.salesProjectRequests,
    null,
    true,
  ),
  _Row(
    'Payables',
    Icons.account_balance_wallet_outlined,
    AppRoutes.salesPayables,
    'Operations',
  ),
  _Row(
    'Deliveries',
    Icons.local_shipping_outlined,
    AppRoutes.salesDeliveries,
  ),
  _Row(
    'Transfers',
    Icons.swap_horiz_rounded,
    AppRoutes.salesTransfers,
  ),
  _Row(
    'Settings',
    Icons.settings_outlined,
    AppRoutes.salesSettings,
  ),
];

const _stockManagerMenu = <_Row>[
  _Row(
    'Dashboard',
    Icons.dashboard_outlined,
    AppRoutes.inventoryDashboard,
    'Inventory',
  ),
  _Row(
    'Products',
    Icons.inventory_2_outlined,
    AppRoutes.inventoryProducts,
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
    'Operations',
  ),
  _Row(
    'Deliveries',
    Icons.local_shipping_outlined,
    AppRoutes.inventoryDeliveries,
  ),
  _Row(
    'Transfers',
    Icons.swap_horiz_rounded,
    AppRoutes.inventoryTransfers,
  ),
  _Row(
    'Import & export',
    Icons.import_export_rounded,
    AppRoutes.inventoryImportExport,
  ),
];

// Owner 2026-11-18: the Admin sees everything (the Dashboard's tabs) and acts
// on nothing, so the menu keeps only the Admin's own jobs. Storage locations,
// categories and suppliers live inside Settings.
const _adminMenu = <_Row>[
  _Row(
    'Dashboard',
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
    'Settings',
    Icons.settings_outlined,
    AppRoutes.adminSettings,
    'Configuration',
  ),
  _Row(
    'Audit logs',
    Icons.history_rounded,
    AppRoutes.adminAuditLogs,
    'Monitoring',
  ),
  _Row(
    'Backup & restore',
    Icons.backup_outlined,
    AppRoutes.adminBackupRestore,
  ),
  _Row('Security', Icons.security_outlined, AppRoutes.adminSecurity),
];

// Decision 25: the Bodega Checker's whole menu - Bodega and nothing else.
const _bodegaMenu = <_Row>[
  _Row(
    'Pick-ups',
    Icons.qr_code_scanner_rounded,
    AppRoutes.bodegaPickups,
    'Bodega',
  ),
  _Row(
    'Deliveries to check',
    Icons.move_to_inbox_outlined,
    AppRoutes.bodegaDeliveries,
  ),
  _Row('Bodega stock', Icons.warehouse_outlined, AppRoutes.bodegaStock),
  _Row('History', Icons.history_rounded, AppRoutes.bodegaHistory),
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

  test('the Bodega menu is the checker menu, row by row', () {
    _expectMenu(AppAreas.bodega, _bodegaMenu);
  });

  test('49 menu rows are 45 pages: only the locked set is shared', () {
    // Without the counts, an empty or duplicated registry would make every
    // per-area check above pass against nothing.
    expect(
      AppDestinations.all,
      hasLength(49),
      reason: '5 menus: Till 9, Sales 13, Stock 17, Admin 6, Bodega 4',
    );
    expect(
      AppDestinations.all.map((row) => row.id).toSet(),
      hasLength(45),
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
      // Owner 2026-11-18: only the Store Manager keeps Reports now.
      final others = [
        ...AppDestinations.forArea(AppAreas.admin),
        ...AppDestinations.forArea(AppAreas.sales),
      ].where((row) => row.id == 'reports');
      expect(others, hasLength(1));
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
        ('Selling', 0),
        ('Customers', 4),
        ('Management', 6),
        ('Operations', 9),
      ],
      AppAreas.inventory: [
        ('Inventory', 0),
        ('Purchasing', 6),
        ('Sales', 9),
        ('Operations', 13),
      ],
      AppAreas.admin: [
        ('Overview', 0),
        ('People', 1),
        ('Configuration', 2),
        ('Monitoring', 3),
      ],
      AppAreas.bodega: [('Bodega', 0)],
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
    // Owner 2026-11-18: the Admin menu no longer has the queue.
    expect(
      AppDestinations.indexOf(
        AppDestinations.projectRequestsId,
        AppAreas.admin,
      ),
      -1,
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
