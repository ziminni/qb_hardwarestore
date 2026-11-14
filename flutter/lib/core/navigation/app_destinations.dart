import 'package:client/core/constants/app_areas.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';

/// One sidebar destination, as ONE area's menu renders it.
///
/// The registry is the single source of the four menus: the Admin, Sales and
/// Stock layouts and the Till shell (plus their route adapters) build their
/// lists from [AppDestinations.all], so a label, icon, route, group heading or
/// position is written once instead of four times.
///
/// 47 rows, 38 identities. A page that exists in several areas (Payables,
/// Deliveries, Reports, Project requests, Staff, Transfers) has one row per area
/// it appears in, all carrying the same [sharedKey]: merged rendering (Phase 2
/// F2) shows such a page once, under the widest assigned area, and de-duplicates
/// by [sharedKey] - never by label. Stock's "Reports" is a DIFFERENT page from
/// the Admin/Sales one, so it has no shared key at all.
class AppDestination {
  const AppDestination({
    required this.id,
    required this.area,
    required this.label,
    required this.icon,
    required this.route,
    this.group,
    this.sharedKey,
    this.badge = false,
  });

  /// Stable identity across areas: `payables` is the same page whether the
  /// Admin, the Store Manager or the Stock Manager opens it.
  final String id;

  /// The area whose menu shows this row ([AppAreas] code, e.g. `pos`).
  final String area;

  final String label;
  final IconData icon;

  /// The route this row opens *in this area* (`/sales/payables` vs
  /// `/inventory/payables`). Read from [AppRoutes], never restated.
  final String route;

  /// The heading this row STARTS, or null when it continues the heading above.
  /// Expressing a group as "where it starts" is what lets the flat index stay
  /// the row's position: grouping cannot renumber anything.
  final String? group;

  /// Same key in two areas means one page body: merged rendering shows it once.
  final String? sharedKey;

  /// The shell's own marker loader (held carts, waiting project requests,
  /// unresolved stock alerts) targets this row. A failed read draws no badge.
  final bool badge;
}

/// The four menus as data, widest authority first within an area's block.
///
/// Declaration order per area IS the flat sidebar index the pages declare
/// (`selectedNavigationIndex`), and every block is append-only: a new row goes
/// last in its area, never in the middle.
class AppDestinations {
  const AppDestinations._();

  /// Every area/identity row, grouped by area in flat index order.
  ///
  /// Read it by area with [forArea]; the rows are written area by area because
  /// the flat index a page declares is its position in its own area's menu.
  static const List<AppDestination> all = <AppDestination>[
    // ---- Till -----------------------------------------------------------------
    AppDestination(
      id: 'pos.new-transaction',
      area: AppAreas.pos,
      label: 'New transaction',
      icon: Icons.point_of_sale_outlined,
      route: AppRoutes.posDashboard,
      group: 'Selling',
    ),
    AppDestination(
      id: 'pos.history',
      area: AppAreas.pos,
      label: 'Transaction history',
      icon: Icons.receipt_long_outlined,
      route: AppRoutes.posHistory,
    ),
    AppDestination(
      id: 'pos.release',
      area: AppAreas.pos,
      label: 'Release materials',
      icon: Icons.inventory_2_outlined,
      route: AppRoutes.posRelease,
      group: 'Customers and projects',
    ),
    AppDestination(
      id: 'pos.record-payment',
      area: AppAreas.pos,
      label: 'Record payment',
      icon: Icons.payments_outlined,
      route: AppRoutes.posReceivables,
    ),
    AppDestination(
      id: 'pos.held',
      area: AppAreas.pos,
      label: 'Held transactions',
      icon: Icons.pause_circle_outline,
      route: AppRoutes.posHeld,
      group: 'Till',
      badge: true,
    ),
    AppDestination(
      id: 'pos.shifts',
      area: AppAreas.pos,
      label: 'Shifts',
      icon: Icons.access_time,
      route: AppRoutes.posShifts,
    ),
    AppDestination(
      id: 'pos.returns',
      area: AppAreas.pos,
      label: 'Returns',
      icon: Icons.assignment_return_outlined,
      route: AppRoutes.posReturns,
    ),

    // ---- Sales ----------------------------------------------------------------
    AppDestination(
      id: 'sales.dashboard',
      area: AppAreas.sales,
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      route: AppRoutes.salesDashboard,
      group: 'Overview',
    ),
    AppDestination(
      id: 'sales.transactions',
      area: AppAreas.sales,
      label: 'Transactions',
      icon: Icons.receipt_long_outlined,
      route: AppRoutes.salesTransactions,
      group: 'Selling',
    ),
    AppDestination(
      id: 'sales.quotations',
      area: AppAreas.sales,
      label: 'Quotations',
      icon: Icons.request_quote_outlined,
      route: AppRoutes.salesQuotations,
    ),
    AppDestination(
      id: 'sales.orders',
      area: AppAreas.sales,
      label: 'Sales orders',
      icon: Icons.assignment_outlined,
      route: AppRoutes.salesOrders,
    ),
    AppDestination(
      id: 'sales.receivables',
      area: AppAreas.sales,
      label: 'Receivables',
      icon: Icons.account_balance_wallet_outlined,
      route: AppRoutes.salesReceivables,
      group: 'Customers',
    ),
    AppDestination(
      id: 'sales.returns',
      area: AppAreas.sales,
      label: 'Returns & refunds',
      icon: Icons.assignment_return_outlined,
      route: AppRoutes.salesReturns,
      group: 'After Sales',
    ),
    // The admin/sales Reports page: one body, two shells (decision 24's locked
    // shared set), so it carries a shared key. The icon differs per area and the
    // admin label is the same word, but the de-duplication keys off the id.
    AppDestination(
      id: 'reports',
      area: AppAreas.sales,
      label: 'Reports',
      icon: Icons.bar_chart_outlined,
      route: AppRoutes.salesReports,
      group: 'Insights',
      sharedKey: 'reports',
    ),
    // Shared Staff keeps the ADMIN label "User management" (Phase 2 F0 ruling);
    // the sales shell has always called it "Staff".
    AppDestination(
      id: 'staff',
      area: AppAreas.sales,
      label: 'Staff',
      icon: Icons.manage_accounts_outlined,
      route: AppRoutes.salesStaff,
      group: 'Management',
      sharedKey: 'staff',
    ),
    AppDestination(
      id: 'project-requests',
      area: AppAreas.sales,
      label: 'Project requests',
      icon: Icons.fact_check_outlined,
      route: AppRoutes.salesProjectRequests,
      group: 'Projects',
      sharedKey: 'project-requests',
      badge: true,
    ),
    AppDestination(
      id: 'payables',
      area: AppAreas.sales,
      label: 'Payables',
      icon: Icons.account_balance_wallet_outlined,
      route: AppRoutes.salesPayables,
      group: 'Payables',
      sharedKey: 'payables',
    ),
    AppDestination(
      id: 'deliveries',
      area: AppAreas.sales,
      label: 'Deliveries',
      icon: Icons.local_shipping_outlined,
      route: AppRoutes.salesDeliveries,
      group: 'Deliveries',
      sharedKey: 'deliveries',
    ),
    AppDestination(
      id: 'transfers',
      area: AppAreas.sales,
      label: 'Transfers',
      icon: Icons.swap_horiz_rounded,
      route: AppRoutes.salesTransfers,
      group: 'Transfers',
      sharedKey: 'transfers',
    ),

    // ---- Stock ----------------------------------------------------------------
    AppDestination(
      id: 'inventory.dashboard',
      area: AppAreas.inventory,
      label: 'Dashboard',
      icon: Icons.dashboard_outlined,
      route: AppRoutes.inventoryDashboard,
      group: 'Overview',
    ),
    AppDestination(
      id: 'inventory.products',
      area: AppAreas.inventory,
      label: 'Products',
      icon: Icons.inventory_2_outlined,
      route: AppRoutes.inventoryProducts,
      group: 'Inventory',
    ),
    AppDestination(
      id: 'inventory.categories',
      area: AppAreas.inventory,
      label: 'Categories',
      icon: Icons.category_outlined,
      route: AppRoutes.inventoryCategories,
    ),
    AppDestination(
      id: 'inventory.stock',
      area: AppAreas.inventory,
      label: 'Stock',
      icon: Icons.warehouse_outlined,
      route: AppRoutes.inventoryStock,
    ),
    // D2: the destination kept its index and route; only the label says what the
    // screen now lists.
    AppDestination(
      id: 'inventory.stock-adjustments',
      area: AppAreas.inventory,
      label: 'Stock adjustments',
      icon: Icons.swap_vert_rounded,
      route: AppRoutes.inventoryStockMovements,
    ),
    AppDestination(
      id: 'inventory.low-stock',
      area: AppAreas.inventory,
      label: 'Low stock',
      icon: Icons.warning_amber_rounded,
      route: AppRoutes.inventoryLowStock,
      badge: true,
    ),
    AppDestination(
      id: 'inventory.purchases',
      area: AppAreas.inventory,
      label: 'Purchases',
      icon: Icons.shopping_bag_outlined,
      route: AppRoutes.inventoryPurchases,
      group: 'Purchasing',
    ),
    AppDestination(
      id: 'inventory.suppliers',
      area: AppAreas.inventory,
      label: 'Suppliers',
      icon: Icons.local_shipping_outlined,
      route: AppRoutes.inventorySuppliers,
    ),
    // Receiving needs its OWN destination: it used to share index 9 with Returns,
    // so the Returns tab opened Receiving and the three tabs after it were
    // unreachable.
    AppDestination(
      id: 'inventory.receiving',
      area: AppAreas.inventory,
      label: 'Receiving',
      icon: Icons.move_to_inbox_outlined,
      route: AppRoutes.inventoryReceiving,
    ),
    AppDestination(
      id: 'inventory.sales',
      area: AppAreas.inventory,
      label: 'Sales',
      icon: Icons.shopping_cart_outlined,
      route: AppRoutes.inventorySales,
      group: 'Sales',
    ),
    AppDestination(
      id: 'inventory.returns',
      area: AppAreas.inventory,
      label: 'Returns',
      icon: Icons.undo_rounded,
      route: AppRoutes.inventoryReturns,
    ),
    // NOT the admin/sales Reports page: this is InventoryReportsPage, so it has no
    // shared key. Same label, same icon family - a different screen.
    AppDestination(
      id: 'inventory.reports',
      area: AppAreas.inventory,
      label: 'Reports',
      icon: Icons.bar_chart_rounded,
      route: AppRoutes.inventoryReports,
    ),
    AppDestination(
      id: 'inventory.settings',
      area: AppAreas.inventory,
      label: 'Settings',
      icon: Icons.settings_outlined,
      route: AppRoutes.inventorySettings,
    ),
    AppDestination(
      id: 'payables',
      area: AppAreas.inventory,
      label: 'Payables',
      icon: Icons.account_balance_wallet_outlined,
      route: AppRoutes.inventoryPayables,
      group: 'Payables',
      sharedKey: 'payables',
    ),
    AppDestination(
      id: 'deliveries',
      area: AppAreas.inventory,
      label: 'Deliveries',
      icon: Icons.local_shipping_outlined,
      route: AppRoutes.inventoryDeliveries,
      group: 'Deliveries',
      sharedKey: 'deliveries',
    ),
    AppDestination(
      id: 'transfers',
      area: AppAreas.inventory,
      label: 'Transfers',
      icon: Icons.swap_horiz_rounded,
      route: AppRoutes.inventoryTransfers,
      group: 'Transfers',
      sharedKey: 'transfers',
    ),

    // ---- Admin ----------------------------------------------------------------
    AppDestination(
      id: 'admin.overview',
      area: AppAreas.admin,
      label: 'Overview',
      icon: Icons.dashboard_outlined,
      route: AppRoutes.adminDashboard,
      group: 'Overview',
    ),
    AppDestination(
      id: 'staff',
      area: AppAreas.admin,
      label: 'User management',
      icon: Icons.manage_accounts_outlined,
      route: AppRoutes.adminUserManagement,
      group: 'People',
      sharedKey: 'staff',
    ),
    AppDestination(
      id: 'admin.inventory',
      area: AppAreas.admin,
      label: 'Inventory',
      icon: Icons.inventory_2_outlined,
      route: AppRoutes.adminInventory,
      group: 'Operations',
    ),
    AppDestination(
      id: 'admin.sales',
      area: AppAreas.admin,
      label: 'Sales & POS',
      icon: Icons.point_of_sale_outlined,
      route: AppRoutes.adminSales,
    ),
    AppDestination(
      id: 'reports',
      area: AppAreas.admin,
      label: 'Reports',
      icon: Icons.bar_chart_rounded,
      route: AppRoutes.adminReports,
      group: 'Insights',
      sharedKey: 'reports',
    ),
    AppDestination(
      id: 'admin.audit-logs',
      area: AppAreas.admin,
      label: 'Audit logs',
      icon: Icons.history_rounded,
      route: AppRoutes.adminAuditLogs,
      group: 'System',
    ),
    AppDestination(
      id: 'admin.settings',
      area: AppAreas.admin,
      label: 'Settings',
      icon: Icons.settings_outlined,
      route: AppRoutes.adminSettings,
    ),
    // The label is short because "Requests from projects" clipped to
    // "Requests from p..." beside its count badge; the page title keeps the long
    // form.
    AppDestination(
      id: 'project-requests',
      area: AppAreas.admin,
      label: 'Project requests',
      icon: Icons.fact_check_outlined,
      route: AppRoutes.adminProjectRequests,
      group: 'Projects',
      sharedKey: 'project-requests',
      badge: true,
    ),
    AppDestination(
      id: 'payables',
      area: AppAreas.admin,
      label: 'Payables',
      icon: Icons.account_balance_wallet_outlined,
      route: AppRoutes.adminPayables,
      group: 'Payables',
      sharedKey: 'payables',
    ),
    AppDestination(
      id: 'deliveries',
      area: AppAreas.admin,
      label: 'Deliveries',
      icon: Icons.local_shipping_outlined,
      route: AppRoutes.adminDeliveries,
      group: 'Deliveries',
      sharedKey: 'deliveries',
    ),
    AppDestination(
      id: 'admin.storage-locations',
      area: AppAreas.admin,
      label: 'Storage locations',
      icon: Icons.warehouse_outlined,
      route: AppRoutes.adminStorageLocations,
      group: 'Locations',
    ),
    AppDestination(
      id: 'transfers',
      area: AppAreas.admin,
      label: 'Transfers',
      icon: Icons.swap_horiz_rounded,
      route: AppRoutes.adminTransfers,
      group: 'Transfers',
      sharedKey: 'transfers',
    ),
  ];

  /// The three ids the shells' own badge loaders and index constants name. A
  /// typo in one of these strings is a compile error, not a badge on the wrong
  /// row.
  static const String projectRequestsId = 'project-requests';
  static const String lowStockId = 'inventory.low-stock';
  static const String heldTransactionsId = 'pos.held';

  /// Ids of the pages that exist in more than one area. Merged de-duplication
  /// keys off these, never off a label; locked by decision 24 and Phase 2 F0.
  static const Set<String> sharedIds = {
    'reports',
    'staff',
    'project-requests',
    'payables',
    'deliveries',
    'transfers',
  };

  /// The rows of [area]'s menu, in flat index order (index = position).
  static List<AppDestination> forArea(String area) => [
    for (final destination in all)
      if (destination.area == area) destination,
  ];

  /// [area]'s menu as the sidebar renders it: a row with a heading starts a new
  /// section, so the sections cannot renumber a destination.
  static List<SharedSidebarSection> sectionsFor(String area) {
    final rows = forArea(area);
    final sections = <SharedSidebarSection>[];
    var start = 0;
    for (var index = 1; index <= rows.length; index++) {
      final boundary = index == rows.length || rows[index].group != null;
      if (!boundary) continue;
      sections.add(
        SharedSidebarSection(
          label: rows[start].group ?? '',
          destinations: [
            for (final row in rows.sublist(start, index))
              SharedSidebarDestination(label: row.label, icon: row.icon),
          ],
        ),
      );
      start = index;
    }
    return sections;
  }

  /// [area]'s section headings as `(heading, first flat index)`.
  static List<(String, int)> groupsFor(String area) {
    final rows = forArea(area);
    return [
      for (var index = 0; index < rows.length; index++)
        if (rows[index].group != null) (rows[index].group!, index),
    ];
  }

  /// The route of flat index [index] in [area], or null when no row owns it.
  static String? routeAt(String area, int index) {
    final rows = forArea(area);
    if (index < 0 || index >= rows.length) return null;
    return rows[index].route;
  }

  /// Flat index of [id] in [area]'s menu, or -1 when that area has no such row.
  ///
  /// The shells' own index constants are const ints (pages pass them in const
  /// maps) and Dart cannot call this from a const expression, so each constant
  /// is pinned to this lookup by `app_destinations_test.dart`.
  static int indexOf(String id, String area) {
    final rows = forArea(area);
    for (var index = 0; index < rows.length; index++) {
      if (rows[index].id == id) return index;
    }
    return -1;
  }

  static List<String> labelsFor(String area) => [
    for (final row in forArea(area)) row.label,
  ];

  static List<String> routesFor(String area) => [
    for (final row in forArea(area)) row.route,
  ];
}
