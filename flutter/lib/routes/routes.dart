import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_durations.dart';
import 'package:client/features/admin/views/admin_user_management_page.dart';
import 'package:client/features/admin/views/audit_logs_page.dart';
import 'package:client/features/admin/views/inventory_monitoring_page.dart';
import 'package:client/features/admin/views/reports_page.dart';
import 'package:client/features/admin/views/sales_monitoring_page.dart';
import 'package:client/features/admin/views/settings_page.dart';
import 'package:client/features/admin/views/storage_locations_page.dart';
import 'package:client/features/categories/views/categories_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/views/area_picker_page.dart';
import 'package:client/features/auth/views/login_page.dart';
import 'package:client/features/auth/views/unsupported_role_page.dart';
import 'package:client/features/dashboard/viewmodels/admin_overview_viewmodel.dart';
import 'package:client/features/dashboard/views/admin_dashboard.dart';
import 'package:client/features/dashboard/views/inventory_dashboard.dart';
import 'package:client/features/pos/views/pos_receivables_page.dart';
import 'package:client/features/pos/views/pos_returns_page.dart';
import 'package:client/features/pos/views/pos_shift_page.dart';
import 'package:client/features/pos/views/pos_held_transactions_page.dart';
import 'package:client/features/pos/views/pos_transaction_history_page.dart';
import 'package:client/features/pos/views/pos_transaction_page.dart';
import 'package:client/features/pos/views/material_release_page.dart';
import 'package:client/features/requisitions/views/project_requests_page.dart';
import 'package:client/features/sales/views/sales_dashboard_page.dart';
import 'package:client/features/sales/views/sales_orders_page.dart';
import 'package:client/features/sales/views/sales_quotations_page.dart';
import 'package:client/features/sales/views/sales_receivables_page.dart';
import 'package:client/features/sales/views/sales_reports_page.dart';
import 'package:client/features/sales/views/sales_returns_page.dart';
import 'package:client/features/sales/views/sales_transactions_page.dart';
import 'package:client/features/inventory/views/inventory_stock_movements_page.dart';
import 'package:client/features/inventory/views/inventory_low_stock_page.dart';
import 'package:client/features/inventory/views/inventory_stock_page.dart';
import 'package:client/features/inventory/views/inventory_receiving_page.dart';
import 'package:client/features/inventory/views/inventory_reports_page.dart';
import 'package:client/features/inventory/views/inventory_returns_page.dart';
import 'package:client/features/inventory/views/inventory_settings_page.dart';
import 'package:client/features/deliveries/views/deliveries_page.dart';
import 'package:client/features/payables/views/payables_page.dart';
import 'package:client/features/transfers/views/transfers_page.dart';
import 'package:client/features/products/views/products_page.dart';
import 'package:client/features/suppliers/views/purchases_page.dart';
import 'package:client/features/suppliers/views/suppliers_page.dart';
import 'package:client/features/sales/views/inventory_sales_page.dart';
import 'package:client/features/sales/views/sales_staff_page.dart';
import 'package:client/features/splash/views/splash_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class AppRoutes {
  AppRoutes._();

  /// The branded intro every start passes through while the session restores.
  static const String splash = '/splash';
  static const String login = '/login';

  /// Where an authenticated account with no POS dashboard is sent.
  /// See [UnsupportedRolePage] and decision 04.
  static const String unsupportedRole = '/unsupported-role';

  /// Where an account holding SEVERAL areas picks the one to work in
  /// (Phase 4 F3b, decision 18).
  ///
  /// No area is active until this screen answers, so every other location
  /// redirects here first. It is not a staff picker: it offers only the areas
  /// the server assigned (see `redirectFor`'s `assignedAreas`).
  static const String areaPicker = '/select-area';
  static const String adminDashboard = '/admin/dashboard';
  static const String adminUserManagement = '/admin/users';
  static const String adminInventory = '/admin/inventory';
  static const String adminSales = '/admin/sales';
  static const String adminReports = '/admin/reports';
  static const String adminAuditLogs = '/admin/audit-logs';
  static const String adminSettings = '/admin/settings';

  /// The "Requests from projects" queue in the Admin shell (Phase 1b,
  /// decisions 09, 10 and 13). Appended under the admin area like every other
  /// admin screen; the Store Manager reaches the same body at
  /// [salesProjectRequests] through [salesTwinOf].
  static const String adminProjectRequests = '/admin/project-requests';

  /// Supplier payables (Phase 5 B2/F2, decision 18), one route per shell.
  ///
  /// Appended to every sidebar it appears in, so no earlier index moved. A
  /// Cashier has none at all: supplier money is not till data, and the area
  /// prefix fence already sends a typed address to the account's own dashboard.
  static const String adminPayables = '/admin/payables';

  /// Customer deliveries (Phase 5 B3/F3, decision 18), one route per shell.
  ///
  /// Appended to every sidebar it appears in, so no earlier index moved. A
  /// Cashier has none: the server scopes a cashier to their own slips but
  /// refuses every status move, so the schedule is the manager's and the stock
  /// manager's to work.
  static const String adminDeliveries = '/admin/deliveries';

  /// Storage locations (Phase 5 B4/F4, decision 18), APPENDED to the Admin
  /// sidebar in a group of its own so no earlier index moved.
  ///
  /// Admin only, and the fence is this `/admin/` prefix: the server writes this
  /// list with `IsAdminRole`, so another account typing the address lands on its
  /// own dashboard rather than a screen whose every button would 403.
  static const String adminStorageLocations = '/admin/storage-locations';

  /// Stock transfers (Phase 9 F3, decision 21 §3), one route per shell.
  ///
  /// APPENDED to every sidebar it appears in, so no earlier index moved. A
  /// Cashier has none at all: moving stock between shelves is the stock team's
  /// job and the server answers 403 to both the list and the write, so a
  /// read-only screen would be an error page.
  static const String adminTransfers = '/admin/transfers';
  static const String inventoryDashboard = '/inventory/dashboard';
  static const String inventoryProducts = '/inventory/products';
  static const String inventoryCategories = '/inventory/categories';
  static const String inventoryStock = '/inventory/stock';
  static const String inventoryStockMovements = '/inventory/stock-movements';
  static const String inventoryLowStock = '/inventory/low-stock';
  static const String inventoryPurchases = '/inventory/purchases';
  static const String inventorySuppliers = '/inventory/suppliers';
  static const String inventorySales = '/inventory/sales';
  static const String inventoryReceiving = '/inventory/receiving';
  static const String inventoryReturns = '/inventory/returns';
  static const String inventoryReports = '/inventory/reports';
  static const String inventoryPayables = '/inventory/payables';
  static const String inventoryDeliveries = '/inventory/deliveries';

  /// The Stock Manager's transfers screen (inventory sidebar index 15).
  static const String inventoryTransfers = '/inventory/transfers';
  static const String inventorySettings = '/inventory/settings';
  static const String posDashboard = '/pos/dashboard';
  static const String posHistory = '/pos/history';
  static const String posRelease = '/pos/release';
  static const String posReceivables = '/pos/receivables';
  static const String posHeld = '/pos/held';
  static const String posShifts = '/pos/shifts';

  /// The till's Returns tab (index 6, decision 05).
  ///
  /// Appended, never inserted: the POS sidebar is append-only, so tabs 0-5 keep
  /// the numbers their own pages declare.
  static const String posReturns = '/pos/returns';
  static const String salesDashboard = '/sales/dashboard';
  static const String salesTransactions = '/sales/transactions';
  static const String salesQuotations = '/sales/quotations';
  static const String salesOrders = '/sales/orders';
  static const String salesReceivables = '/sales/receivables';
  static const String salesReturns = '/sales/returns';

  /// The Store Manager's Reports tab (sales sidebar index 6, decision D-01).
  ///
  /// Separate from [adminReports] on purpose: the same report content, but in
  /// the SALES shell, so the manager's sidebar does not swap out.
  static const String salesReports = '/sales/reports';

  /// The Store Manager's staff list (sales sidebar index 7). The same screen as
  /// [adminUserManagement], in the SALES shell, so the manager can reach it
  /// from their own sidebar and keep it (the D-01 pattern used for Reports).
  ///
  /// The approval queue that sat beside it is gone (decision 01): requests are
  /// approved in CPMS, so the POS has no queue to open.
  static const String salesStaff = '/sales/staff';

  /// The Store Manager's "Requests from projects" queue (sales sidebar index 8).
  ///
  /// The same screen body as [adminProjectRequests], in the SALES shell, so the
  /// manager answers project requests without swapping sidebars (the D-01
  /// pattern used for Reports and Staff).
  static const String salesProjectRequests = '/sales/project-requests';

  /// The Store Manager's payables screen (sales sidebar index 9): the same body
  /// as [adminPayables], in the manager's own shell.
  static const String salesPayables = '/sales/payables';

  /// The Store Manager's delivery schedule (sales sidebar index 10): the same
  /// body as [adminDeliveries], in the manager's own shell.
  static const String salesDeliveries = '/sales/deliveries';

  /// The Store Manager's transfers screen (sales sidebar index 11): the same
  /// body as [adminTransfers], in the manager's own shell.
  static const String salesTransfers = '/sales/transfers';

  /// The sales-shell twin of an admin screen the Store Manager may use, or null
  /// when [location] has no twin.
  ///
  /// A manager who types `/admin/reports` should land on the same screen in
  /// their own shell, not the Admin sidebar whose other links bounce them.
  static String? salesTwinOf(String location) => switch (location) {
    adminReports => salesReports,
    adminUserManagement => salesStaff,
    adminProjectRequests => salesProjectRequests,
    adminPayables => salesPayables,
    adminDeliveries => salesDeliveries,
    adminTransfers => salesTransfers,
    _ => null,
  };

  /// The pure routing decision: where a request to [location] should go, or null
  /// to stay.
  ///
  /// Extracted from the router's `redirect` closure so the role rules are
  /// testable **without rendering a dashboard**. Every dashboard is built on the
  /// same skeleton, whose existing layout assertions fire under a widget test,
  /// so a routing test that rendered one would fail for a reason that has
  /// nothing to do with routing.
  /// Where the splash sits while the session is still being restored, carrying
  /// the location that was asked for.
  static String splashFrom(String location) =>
      '$splash?from=${Uri.encodeComponent(location)}';

  /// Where the splash hands over once the session is known.
  ///
  /// [from] is the `?from=` a pre-restore redirect carried (a deep link). The
  /// wanted page wins when the active area may open it; otherwise the rules in
  /// [redirectFor] decide (area picker, dashboard, unsupported-role screen,
  /// login).
  static String splashDestination({
    required bool isAuthenticated,
    required String? role,
    String? from,
    List<String> assignedAreas = const [],
  }) {
    final wanted =
        (from == null || from.isEmpty || from == '/' || from == splash)
        ? login
        : from;
    return redirectFor(
          isAuthenticated: isAuthenticated,
          role: role,
          location: wanted,
          assignedAreas: assignedAreas,
        ) ??
        wanted;
  }

  /// The pure routing decision: where a request to [location] should go, or null
  /// to stay.
  ///
  /// [role] is the ACTIVE area, not the whole authority: an account may hold
  /// several areas ([assignedAreas]) and works in one at a time. With no active
  /// area and several assigned, nothing opens before the picker answers. A call
  /// passing no [assignedAreas] keeps the released single-role behaviour, where
  /// the [role] argument is the whole assignment.
  static String? redirectFor({
    required bool isAuthenticated,
    required String? role,
    required String location,
    bool isInitializing = false,
    List<String> assignedAreas = const [],
  }) {
    // The splash owns its own exit: it hands over once the restore settles, so
    // a redirect must not cut its intro short or bounce it to the login screen.
    if (location == splash) return null;

    // Startup: the session is not known yet. Park the requested location on the
    // splash instead of answering the role question with "not signed in", which
    // would drop a deep link on the login screen.
    // shortcut: only the path survives, not its query string (no deep link in
    // the app carries one today); rebuild from state.uri when one does.
    if (isInitializing) return splashFrom(location);

    final isLogin = location == login;
    final isUnsupported = location == unsupportedRole;
    final isPicker = location == areaPicker;

    if (!isAuthenticated) return isLogin ? null : login;

    final areas = assignedAreas.isEmpty
        ? [if (role != null && role.isNotEmpty) role]
        : assignedAreas;
    // The active area is the account's own choice, honoured only while the
    // server still assigns it. One assigned area needs no choice at all.
    final active = (role != null && areas.contains(role))
        ? role
        : (areas.length == 1 ? areas.single : null);

    if (areas.isEmpty) {
      // Decision 04: an unmapped or role-less account gets an explicit screen,
      // never a silent bounce to `/login` while apparently signed in. Returning
      // null when already there is what stops this from looping.
      return isUnsupported ? null : unsupportedRole;
    }
    if (active == null) {
      // Several areas and none chosen yet: the picker is the only screen.
      return isPicker ? null : areaPicker;
    }

    final dashboard = dashboardForRole(active);
    if (dashboard == null) {
      return isUnsupported ? null : unsupportedRole;
    }
    if (isLogin || isUnsupported || isPicker) return dashboard;
    if (location.startsWith('/admin/') && active != AppAreas.admin) {
      // Decision 16: the Store Manager (client role 'sales') is the month-end
      // actor, and IsManagerRole admits them server-side, so the fence opens for
      // the reports screen only. Phase 5: the manager offboards staff in-app and
      // IsUserManagerRole admits them server-side, so user management opens
      // too. Audit logs and settings stay admin-only; Cashier ('pos') and
      // Stock Manager ('inventory') still bounce everywhere here.
      // Decisions 16 and 20 + Phase 5 still hold: the manager reaches reports
      // and staff, but in the sales shell (Z2).
      if (active == AppAreas.sales) return salesTwinOf(location) ?? dashboard;
      return dashboard;
    }
    if (location.startsWith('/inventory/') && active != AppAreas.inventory) {
      return dashboard;
    }
    if (location.startsWith('/sales/') && active != AppAreas.sales) {
      return dashboard;
    }
    // The till's own area, fenced like every other one: a typed /pos address
    // from an account working elsewhere opens that account's dashboard.
    if (location.startsWith('/pos/') && active != AppAreas.pos) {
      return dashboard;
    }

    const protectedDashboards = {
      adminDashboard,
      inventoryDashboard,
      posDashboard,
      salesDashboard,
    };
    if (protectedDashboards.contains(location) && location != dashboard) {
      return dashboard;
    }
    return null;
  }

  static String? dashboardForRole(String? role) {
    return switch (role) {
      AppAreas.admin => adminDashboard,
      AppAreas.inventory => inventoryDashboard,
      AppAreas.pos => posDashboard,
      AppAreas.sales => salesDashboard,
      _ => null,
    };
  }

  static CustomTransitionPage<void> _transitionPage(
    GoRouterState state,
    Widget child,
  ) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: child,
      // Short and fade-only: every sidebar click goes through this, and the
      // old 300 ms fade plus slide made switching tabs feel slow.
      transitionDuration: AppDurations.fast,
      reverseTransitionDuration: AppDurations.fast,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
          child: child,
        );
      },
    );
  }

  static GoRouter createRouter(AuthViewmodel auth) {
    return GoRouter(
      initialLocation: splash,
      refreshListenable: auth,
      // An address no route matches (e.g. a retired /admin/requisitions) goes to
      // the user's own dashboard instead of GoRouter's debug "Page Not Found".
      onException: (context, state, router) =>
          router.go(dashboardForRole(auth.roleName) ?? login),
      redirect: (context, state) => redirectFor(
        isAuthenticated: auth.isAuthenticated,
        role: auth.roleName,
        location: state.matchedLocation,
        isInitializing: auth.isInitializing,
        assignedAreas: auth.assignedAreas,
      ),
      routes: [
        GoRoute(
          path: splash,
          name: 'splash',
          // No transition: the page is the first frame, not a navigation.
          pageBuilder: (context, state) =>
              NoTransitionPage(key: state.pageKey, child: const SplashPage()),
        ),
        GoRoute(
          path: login,
          name: 'login',
          pageBuilder: (context, state) =>
              _transitionPage(state, const LoginPage()),
        ),
        GoRoute(
          path: unsupportedRole,
          name: 'unsupported_role',
          pageBuilder: (context, state) =>
              _transitionPage(state, const UnsupportedRolePage()),
        ),
        GoRoute(
          path: areaPicker,
          name: 'area_picker',
          pageBuilder: (context, state) =>
              _transitionPage(state, const AreaPickerPage()),
        ),
        GoRoute(
          path: adminDashboard,
          name: 'admin_dashboard',
          // Route-scoped viewmodel, matching AdminUserManagementPage: the
          // dashboard loads fresh data on every open, and nothing else reads
          // an overview. Without this provider the page threw
          // ProviderNotFoundException before rendering a single metric.
          pageBuilder: (context, state) => _transitionPage(
            state,
            ChangeNotifierProvider(
              create: (_) => AdminOverviewViewmodel(),
              child: const AdminDashboard(),
            ),
          ),
        ),
        GoRoute(
          path: adminUserManagement,
          name: 'admin_user_management',
          pageBuilder: (context, state) =>
              _transitionPage(state, const AdminUserManagementPage()),
        ),
        GoRoute(
          path: adminInventory,
          name: 'admin_inventory',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventoryMonitoringPage()),
        ),
        GoRoute(
          path: adminSales,
          name: 'admin_sales',
          pageBuilder: (context, state) =>
              _transitionPage(state, const SalesMonitoringPage()),
        ),
        GoRoute(
          path: adminReports,
          name: 'admin_reports',
          pageBuilder: (context, state) =>
              _transitionPage(state, const ReportsPage()),
        ),
        GoRoute(
          path: adminAuditLogs,
          name: 'admin_audit_logs',
          pageBuilder: (context, state) =>
              _transitionPage(state, const AuditLogsPage()),
        ),
        GoRoute(
          path: adminProjectRequests,
          name: 'admin_project_requests',
          pageBuilder: (context, state) =>
              _transitionPage(state, const AdminProjectRequestsPage()),
        ),
        GoRoute(
          path: adminPayables,
          name: 'admin_payables',
          pageBuilder: (context, state) =>
              _transitionPage(state, const AdminPayablesPage()),
        ),
        GoRoute(
          path: adminDeliveries,
          name: 'admin_deliveries',
          pageBuilder: (context, state) =>
              _transitionPage(state, const AdminDeliveriesPage()),
        ),
        GoRoute(
          path: adminStorageLocations,
          name: 'admin_storage_locations',
          pageBuilder: (context, state) =>
              _transitionPage(state, const StorageLocationsPage()),
        ),
        GoRoute(
          path: adminTransfers,
          name: 'admin_transfers',
          pageBuilder: (context, state) =>
              _transitionPage(state, const AdminTransfersPage()),
        ),
        GoRoute(
          path: adminSettings,
          name: 'admin_settings',
          pageBuilder: (context, state) =>
              _transitionPage(state, const SettingsPage()),
        ),
        GoRoute(
          path: inventoryDashboard,
          name: 'inventory_dashboard',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventoryDashboard()),
        ),
        GoRoute(
          path: inventoryProducts,
          name: 'inventory_products',
          pageBuilder: (context, state) =>
              _transitionPage(state, const ProductsPage()),
        ),
        GoRoute(
          path: inventoryCategories,
          name: 'inventory_categories',
          pageBuilder: (context, state) =>
              _transitionPage(state, const CategoriesPage()),
        ),
        GoRoute(
          path: inventoryStock,
          name: 'inventory_stock',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventoryStockPage()),
        ),
        GoRoute(
          path: inventoryStockMovements,
          name: 'inventory_stock_movements',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventoryStockMovementsPage()),
        ),
        GoRoute(
          path: inventoryLowStock,
          name: 'inventory_low_stock',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventoryLowStockPage()),
        ),
        GoRoute(
          path: inventoryPurchases,
          name: 'inventory_purchases',
          pageBuilder: (context, state) =>
              _transitionPage(state, const PurchasesPage()),
        ),
        GoRoute(
          path: inventorySuppliers,
          name: 'inventory_suppliers',
          pageBuilder: (context, state) =>
              _transitionPage(state, const SuppliersPage()),
        ),
        GoRoute(
          path: inventorySales,
          name: 'inventory_sales',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventorySalesPage()),
        ),
        GoRoute(
          path: inventoryReceiving,
          name: 'inventory_receiving',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventoryReceivingPage()),
        ),
        GoRoute(
          path: inventoryReturns,
          name: 'inventory_returns',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventoryReturnsPage()),
        ),
        GoRoute(
          path: inventoryReports,
          name: 'inventory_reports',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventoryReportsPage()),
        ),
        GoRoute(
          path: inventoryPayables,
          name: 'inventory_payables',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventoryPayablesPage()),
        ),
        GoRoute(
          path: inventoryDeliveries,
          name: 'inventory_deliveries',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventoryDeliveriesPage()),
        ),
        GoRoute(
          path: inventoryTransfers,
          name: 'inventory_transfers',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventoryTransfersPage()),
        ),
        GoRoute(
          path: inventorySettings,
          name: 'inventory_settings',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventorySettingsPage()),
        ),
        GoRoute(
          path: posDashboard,
          name: 'pos_dashboard',
          pageBuilder: (context, state) =>
              _transitionPage(state, const PosTransactionPage()),
        ),
        GoRoute(
          path: posHistory,
          name: 'pos_history',
          pageBuilder: (context, state) =>
              _transitionPage(state, const PosTransactionHistoryPage()),
        ),
        GoRoute(
          path: posRelease,
          name: 'pos_release',
          pageBuilder: (context, state) =>
              _transitionPage(state, const MaterialReleasePage()),
        ),
        GoRoute(
          path: posReceivables,
          name: 'pos_receivables',
          pageBuilder: (context, state) =>
              _transitionPage(state, const PosReceivablesPage()),
        ),
        GoRoute(
          path: posHeld,
          name: 'pos_held',
          pageBuilder: (context, state) =>
              _transitionPage(state, const PosHeldTransactionsPage()),
        ),
        GoRoute(
          path: posShifts,
          name: 'pos_shifts',
          pageBuilder: (context, state) =>
              _transitionPage(state, const PosShiftPage()),
        ),
        // The page builds its own returns and shift viewmodels — the same
        // page-owned pattern the Shifts tab uses — so this route declares no
        // provider. A route that NEEDED one and did not provide it is exactly
        // how AdminDashboard crashed with ProviderNotFoundException.
        GoRoute(
          path: posReturns,
          name: 'pos_returns',
          pageBuilder: (context, state) =>
              _transitionPage(state, const PosReturnsPage()),
        ),
        GoRoute(
          path: salesDashboard,
          name: 'sales_dashboard',
          pageBuilder: (context, state) =>
              _transitionPage(state, const SalesDashboardPage()),
        ),
        GoRoute(
          path: salesTransactions,
          name: 'sales_transactions',
          pageBuilder: (context, state) =>
              _transitionPage(state, const SalesTransactionsPage()),
        ),
        GoRoute(
          path: salesQuotations,
          name: 'sales_quotations',
          pageBuilder: (context, state) =>
              _transitionPage(state, const SalesQuotationsPage()),
        ),
        GoRoute(
          path: salesOrders,
          name: 'sales_orders',
          pageBuilder: (context, state) =>
              _transitionPage(state, const SalesOrdersPage()),
        ),
        GoRoute(
          path: salesReceivables,
          name: 'sales_receivables',
          pageBuilder: (context, state) =>
              _transitionPage(state, const SalesReceivablesPage()),
        ),
        GoRoute(
          path: salesReturns,
          name: 'sales_returns',
          pageBuilder: (context, state) =>
              _transitionPage(state, const SalesReturnsPage()),
        ),
        GoRoute(
          path: salesReports,
          name: 'sales_reports',
          pageBuilder: (context, state) =>
              _transitionPage(state, const SalesReportsPage()),
        ),
        GoRoute(
          path: salesProjectRequests,
          name: 'sales_project_requests',
          pageBuilder: (context, state) =>
              _transitionPage(state, const ProjectRequestsPage()),
        ),
        GoRoute(
          path: salesPayables,
          name: 'sales_payables',
          pageBuilder: (context, state) =>
              _transitionPage(state, const SalesPayablesPage()),
        ),
        GoRoute(
          path: salesDeliveries,
          name: 'sales_deliveries',
          pageBuilder: (context, state) =>
              _transitionPage(state, const SalesDeliveriesPage()),
        ),
        GoRoute(
          path: salesTransfers,
          name: 'sales_transfers',
          pageBuilder: (context, state) =>
              _transitionPage(state, const SalesTransfersPage()),
        ),
        GoRoute(
          path: salesStaff,
          name: 'sales_staff',
          pageBuilder: (context, state) =>
              _transitionPage(state, const SalesStaffPage()),
        ),
      ],
    );
  }
}
