import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_durations.dart';
import 'package:client/features/admin/views/admin_backup_restore_page.dart';
import 'package:client/features/admin/views/admin_security_page.dart';
import 'package:client/features/admin/views/admin_user_management_page.dart';
import 'package:client/features/admin/views/audit_logs_page.dart';
import 'package:client/features/admin/views/settings_page.dart';
import 'package:client/features/categories/views/categories_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/views/area_picker_page.dart';
import 'package:client/features/auth/views/login_page.dart';
import 'package:client/features/auth/views/unsupported_role_page.dart';
import 'package:client/features/admin/views/admin_dashboard_page.dart';
import 'package:client/features/dashboard/views/combined_dashboard_page.dart';
import 'package:client/features/dashboard/views/inventory_dashboard.dart';
import 'package:client/features/bodega/views/bodega_pages.dart';
import 'package:client/features/pos/views/pos_customers_page.dart';
import 'package:client/features/pos/views/pos_readings_page.dart';
import 'package:client/features/pos/views/pos_receivables_page.dart';
import 'package:client/features/pos/views/pos_returns_page.dart';
import 'package:client/features/pos/views/pos_sales_orders_page.dart';
import 'package:client/features/pos/views/pos_settings_page.dart';
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
import 'package:client/features/reports/report_catalogue.dart';
import 'package:client/features/reports/report_viewer_page.dart';
import 'package:client/features/reports/reports_browser_page.dart';
import 'package:client/features/reports/reports_shell.dart';
import 'package:client/features/sales/views/sales_returns_page.dart';
import 'package:client/features/sales/views/sales_settings_page.dart';
import 'package:client/features/sales/views/sales_transactions_page.dart';
import 'package:client/features/inventory/views/inventory_stock_movements_page.dart';
import 'package:client/features/inventory/views/inventory_low_stock_page.dart';
import 'package:client/features/inventory/views/inventory_stock_page.dart';
import 'package:client/features/inventory/views/inventory_receiving_page.dart';
import 'package:client/features/inventory/views/inventory_reports_page.dart';
import 'package:client/features/inventory/views/inventory_returns_page.dart';
import 'package:client/features/inventory/views/inventory_import_export_page.dart';
import 'package:client/features/inventory/views/inventory_settings_page.dart';
import 'package:client/features/deliveries/views/deliveries_page.dart';
import 'package:client/features/payables/views/payables_page.dart';
import 'package:client/features/transfers/views/transfers_page.dart';
import 'package:client/features/products/views/price_list_page.dart';
import 'package:client/features/products/views/products_page.dart';
import 'package:client/features/suppliers/views/purchases_page.dart';
import 'package:client/features/suppliers/views/suppliers_page.dart';
import 'package:client/features/sales/views/inventory_sales_page.dart';
import 'package:client/features/sales/views/sales_staff_page.dart';
import 'package:client/features/splash/views/splash_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

  /// Where an account holding SEVERAL areas lands (Phase 2 F3, decision 24):
  /// one page carrying every assigned area's "needs you" tiles.
  ///
  /// Registered by Phase 2 F4 ([CombinedDashboardPage]).
  static const String combinedDashboard = '/dashboard';
  static const String adminDashboard = '/admin/dashboard';
  static const String adminUserManagement = '/admin/users';
  static const String adminInventory = '/admin/inventory';
  static const String adminSales = '/admin/sales';
  static const String adminReports = '/admin/reports';
  static const String adminAuditLogs = '/admin/audit-logs';
  static const String adminBackupRestore = '/admin/backup-restore';
  static const String adminSecurity = '/admin/security';
  static const String adminSettings = '/admin/settings';

  /// Kept only so an old bookmark still redirects (owner 2026-11-18 removed
  /// Reports and Project requests from the Admin menu): a Store Manager is sent
  /// to the sales twin by [salesTwinOf]; an Admin to the dashboard.
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

  /// The stocker's catalogue home and viewer: the SAME bodies as the sales pair,
  /// in the inventory shell. An inventory-only account only ever reaches these,
  /// and the catalogue shows it the INVENTORY section alone
  /// (decision 02-role-visibility: Sales, VAT and profit reports are
  /// `IsManagerRole` server-side).
  static const String inventoryReportCatalogue = '/inventory/reports/catalogue';
  static const String inventoryReportViewer =
      '/inventory/reports/view/:reportId';
  static const String inventoryPayables = '/inventory/payables';
  static const String inventoryDeliveries = '/inventory/deliveries';

  /// The Stock Manager's transfers screen (inventory sidebar index 15).
  static const String inventoryTransfers = '/inventory/transfers';
  static const String inventorySettings = '/inventory/settings';

  /// Every import and export the stocker has (owner 2026-11-18), APPENDED to the
  /// Stock menu.
  static const String inventoryImportExport = '/inventory/import-export';
  static const String inventoryPriceList = '/inventory/price-list';

  /// The Bodega Checker's area (decision 25). `/bodega/` is fenced like every
  /// other area prefix: only an account holding `bodega` opens it.
  static const String bodegaPickups = '/bodega/pickups';
  static const String bodegaDeliveries = '/bodega/deliveries';
  static const String bodegaStock = '/bodega/stock';
  static const String bodegaHistory = '/bodega/history';
  static const String posDashboard = '/pos/dashboard';
  static const String posHistory = '/pos/history';

  /// The till's OR-tagged tab: the slips already tagged with the paper OR
  /// number, and the ones still to tag.
  ///
  /// INSERTED right after [posHistory] at the owner's request — the one
  /// exception to the append-only rule below. Every till tab after it keeps its
  /// page and moved its declared index one down; `sidebar_index_consistency_test`
  /// pins each page to its row.
  static const String posOrTagged = '/pos/or-tagged';
  static const String posRelease = '/pos/release';
  static const String posReceivables = '/pos/receivables';
  static const String posHeld = '/pos/held';
  static const String posShifts = '/pos/shifts';

  /// The till's Returns tab (index 7, decision 05).
  ///
  /// Appended when it landed, so tabs 0-5 kept the numbers their own pages
  /// declare; the OR-tagged tab later took index 2 and moved this one to 7.
  static const String posReturns = '/pos/returns';

  /// The till's Settings tab (the receipt printer), appended after Returns.
  static const String posSettings = '/pos/settings';

  /// The till's Customers tab (index 8): regular customers with standing
  /// discount, utang, and delivery presets for "Who is this sale for?".
  static const String posCustomers = '/pos/customers';
  static const String posDeliveries = '/pos/deliveries';
  static const String posReadings = '/pos/readings';
  static const String posSalesOrders = '/pos/sales-orders';
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

  /// The Reports suite's catalogue home and shared viewer (planning/reports-suite,
  /// decision 02-role-visibility): a card per report, one viewer per report id.
  ///
  /// Sub-paths of the Reports tab rather than new sidebar entries, so the
  /// manager's Reports tab keeps index 6 and the stocker's keeps index 10.
  static const String salesReportCatalogue = '/sales/reports/catalogue';
  static const String salesReportViewer = '/sales/reports/view/:reportId';

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

  /// The Store Manager's settings screen (sales sidebar index 12): store
  /// details and local-device theme settings.
  static const String salesSettings = '/sales/settings';
  static const String salesPriceList = '/sales/price-list';

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
  /// [role] is the ACTIVE area, not the whole authority. A call passing no
  /// [assignedAreas] keeps the released single-role behaviour, where the [role]
  /// argument is the whole assignment. With ONE assigned area the Phase 4 rules
  /// hold unchanged. With SEVERAL (Phase 2 F3, decision 24) the account works
  /// from the union: no active area, no picker, every held prefix open, and the
  /// [combinedDashboard] for everything else.
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

    // Known areas only, each once: an unknown code is no area at all
    // (decision 04), and the same area listed twice is still ONE area, so
    // neither can turn a single-area account into a merged one.
    final areas = <String>{
      ...(assignedAreas.isEmpty
          ? [if (role != null && role.isNotEmpty) role]
          : assignedAreas),
    }.where(AppAreas.contains).toList();

    if (areas.isEmpty) {
      // Decision 04: an unmapped or role-less account gets an explicit screen,
      // never a silent bounce to `/login` while apparently signed in. Returning
      // null when already there is what stops this from looping.
      return isUnsupported ? null : unsupportedRole;
    }
    if (areas.length > 1) {
      // Decision 24: several areas are worked as one, so nothing waits on a
      // pick and the fences check the union instead of one active area.
      return _redirectMerged(
        areas: areas,
        location: location,
        isLogin: isLogin,
        isUnsupported: isUnsupported,
        isPicker: isPicker,
      );
    }

    // One area: unchanged Phase 4 rules, where that area IS the assignment.
    final active = (role != null && areas.contains(role)) ? role : areas.single;

    final dashboard = dashboardForRole(active);
    if (dashboard == null) {
      return isUnsupported ? null : unsupportedRole;
    }
    if (isLogin || isUnsupported || isPicker) return dashboard;
    // The merged landing belongs to accounts with several areas; a single-area
    // account has its own dashboard and must never render the merged page.
    if (location == combinedDashboard) return dashboard;
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
    if (location.startsWith('/bodega/') && active != AppAreas.bodega) {
      return dashboard;
    }

    const protectedDashboards = {
      adminDashboard,
      inventoryDashboard,
      posDashboard,
      salesDashboard,
      bodegaPickups,
    };
    if (protectedDashboards.contains(location) && location != dashboard) {
      return dashboard;
    }
    return null;
  }

  /// The merged-account decision (Phase 2 F3, decision 24).
  ///
  /// [areas] holds the distinct assigned areas, so every prefix in it opens and
  /// one it does not hold goes to [combinedDashboard]. An `/admin` address the
  /// account may use but does not hold as an area goes through [salesTwinOf]
  /// first, so a Store Manager + Cashier types `/admin/reports` and lands on the
  /// same screen in the sales shell. Holding Admin opens the admin originals.
  static String? _redirectMerged({
    required List<String> areas,
    required String location,
    required bool isLogin,
    required bool isUnsupported,
    required bool isPicker,
  }) {
    // The picker is skipped for these accounts, and login and the unsupported
    // screen have nothing to ask them: all three hand over to the landing.
    if (isLogin || isUnsupported || isPicker) return combinedDashboard;
    // The landing is the end of the walk; redirecting it to itself would loop.
    if (location == combinedDashboard) return null;

    final prefixArea = _areaOfPrefix(location);
    if (prefixArea == null) {
      // An address outside the four areas is not an area question: the router's
      // not-found handling answers it, exactly as it does for one area.
      return null;
    }
    if (areas.contains(prefixArea)) return null;
    if (prefixArea == AppAreas.admin && areas.contains(AppAreas.sales)) {
      return salesTwinOf(location) ?? combinedDashboard;
    }
    return combinedDashboard;
  }

  /// The area a location's first path segment belongs to, or null for an
  /// address no area owns.
  static String? _areaOfPrefix(String location) {
    if (location.startsWith('/admin/')) return AppAreas.admin;
    if (location.startsWith('/inventory/')) return AppAreas.inventory;
    if (location.startsWith('/sales/')) return AppAreas.sales;
    if (location.startsWith('/pos/')) return AppAreas.pos;
    if (location.startsWith('/bodega/')) return AppAreas.bodega;
    return null;
  }

  /// Where an account belongs when an address opens nothing: its own area's
  /// dashboard, or [combinedDashboard] for a merged account. Falls back to the
  /// login form for an account that holds no area at all.
  static String landingFor({
    required String? role,
    required List<String> assignedAreas,
  }) {
    if (assignedAreas.toSet().length > 1) return combinedDashboard;
    return dashboardForRole(role) ?? login;
  }

  static String? dashboardForRole(String? role) {
    return switch (role) {
      AppAreas.admin => adminDashboard,
      AppAreas.inventory => inventoryDashboard,
      AppAreas.pos => posDashboard,
      AppAreas.sales => salesDashboard,
      AppAreas.bodega => bodegaPickups,
      _ => null,
    };
  }

  /// The shared viewer for one catalogue card, or the catalogue itself when the
  /// address names no report in [reportCatalogue] (a retired or mistyped id).
  static Widget _reportViewer(String? reportId, ReportsShell shell) {
    final report = reportById(reportId ?? '');
    if (report == null) return ReportsBrowserPage(shell: shell);
    return ReportViewerPage(report: report, shell: shell);
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
      onException: (context, state, router) {
        final landing = landingFor(
          role: auth.roleName,
          assignedAreas: auth.assignedAreas,
        );
        // The combined landing has no page until F4 registers it, so going
        // there from there would loop; the unmatched address stays put instead.
        if (state.uri.path == landing) return;
        router.go(landing);
      },
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
        // Owner 2026-11-18: the Admin sees everything and acts on nothing. The
        // operational admin pages (inventory and sales monitoring, payables,
        // deliveries, transfers) are gone; their typed addresses land on the
        // dashboard (onException) and the constants stay for salesTwinOf.
        GoRoute(
          path: adminDashboard,
          name: 'admin_dashboard',
          // Owner 2026-11-18: the Admin's own tabbed dashboard (System, Sales,
          // Inventory, Bodega, Finance), fed by /reports/admin-dashboard/.
          pageBuilder: (context, state) =>
              _transitionPage(state, const AdminDashboardPage()),
        ),
        GoRoute(
          path: combinedDashboard,
          name: 'combined_dashboard',
          pageBuilder: (context, state) =>
              _transitionPage(state, const CombinedDashboardPage()),
        ),
        GoRoute(
          path: adminUserManagement,
          name: 'admin_user_management',
          pageBuilder: (context, state) =>
              _transitionPage(state, const AdminUserManagementPage()),
        ),
        GoRoute(
          path: adminAuditLogs,
          name: 'admin_audit_logs',
          pageBuilder: (context, state) =>
              _transitionPage(state, const AuditLogsPage()),
        ),
        GoRoute(
          path: adminBackupRestore,
          name: 'admin_backup_restore',
          pageBuilder: (context, state) =>
              _transitionPage(state, const AdminBackupRestorePage()),
        ),
        GoRoute(
          path: adminSecurity,
          name: 'admin_security',
          pageBuilder: (context, state) =>
              _transitionPage(state, const AdminSecurityPage()),
        ),
        GoRoute(
          path: adminStorageLocations,
          name: 'admin_storage_locations',
          // Owner 2026-11-18: Storage locations lives in Settings; the old
          // address opens Settings on that side tab.
          pageBuilder: (context, state) => _transitionPage(
            state,
            const SettingsPage(initialSection: SettingsSection.locations),
          ),
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
        // The stocker's catalogue home and viewer: the same two bodies as the
        // sales pair, in the inventory shell (decision 02-role-visibility).
        GoRoute(
          path: inventoryReportCatalogue,
          name: 'inventory_report_catalogue',
          pageBuilder: (context, state) => _transitionPage(
            state,
            const ReportsBrowserPage(shell: ReportsShell.inventory),
          ),
        ),
        GoRoute(
          path: inventoryReportViewer,
          name: 'inventory_report_viewer',
          pageBuilder: (context, state) => _transitionPage(
            state,
            _reportViewer(
              state.pathParameters['reportId'],
              ReportsShell.inventory,
            ),
          ),
        ),
        GoRoute(
          path: inventoryPayables,
          name: 'inventory_payables',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventoryPayablesPage()),
        ),
        // Customer deliveries belong to Store Manager and Cashier; Stock Manager
        // no longer works customer deliveries.
        GoRoute(
          path: inventoryTransfers,
          name: 'inventory_transfers',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventoryTransfersPage()),
        ),
        // ---- Bodega (decision 25) ----------------------------------------
        GoRoute(
          path: bodegaPickups,
          name: 'bodega_pickups',
          pageBuilder: (context, state) =>
              _transitionPage(state, const BodegaPickupsPage()),
        ),
        GoRoute(
          path: bodegaDeliveries,
          name: 'bodega_deliveries',
          pageBuilder: (context, state) =>
              _transitionPage(state, const BodegaDeliveriesPage()),
        ),
        GoRoute(
          path: bodegaStock,
          name: 'bodega_stock',
          pageBuilder: (context, state) =>
              _transitionPage(state, const BodegaStockPage()),
        ),
        GoRoute(
          path: bodegaHistory,
          name: 'bodega_history',
          pageBuilder: (context, state) =>
              _transitionPage(state, const BodegaHistoryPage()),
        ),
        GoRoute(
          path: inventoryImportExport,
          name: 'inventory_import_export',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventoryImportExportPage()),
        ),
        // Price list belongs to Store Manager only; Stock Manager focuses on
        // stock, purchasing, receiving, and supplier returns.
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
          path: posSettings,
          name: 'pos_settings',
          pageBuilder: (context, state) =>
              _transitionPage(state, const PosSettingsPage()),
        ),
        GoRoute(
          path: posCustomers,
          name: 'pos_customers',
          pageBuilder: (context, state) =>
              _transitionPage(state, const PosCustomersPage()),
        ),
        GoRoute(
          path: posDeliveries,
          name: 'pos_deliveries',
          pageBuilder: (context, state) =>
              _transitionPage(state, const PosDeliveriesPage()),
        ),
        GoRoute(
          path: posReadings,
          name: 'pos_readings',
          pageBuilder: (context, state) =>
              _transitionPage(state, const PosReadingsPage()),
        ),
        GoRoute(
          path: posSalesOrders,
          name: 'pos_sales_orders',
          pageBuilder: (context, state) =>
              _transitionPage(state, const PosSalesOrdersPage()),
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
        // The Reports suite's catalogue home; the five live cards open the
        // shared viewer below with their own report id.
        GoRoute(
          path: salesReportCatalogue,
          name: 'sales_report_catalogue',
          pageBuilder: (context, state) => _transitionPage(
            state,
            const ReportsBrowserPage(shell: ReportsShell.sales),
          ),
        ),
        GoRoute(
          path: salesReportViewer,
          name: 'sales_report_viewer',
          pageBuilder: (context, state) => _transitionPage(
            state,
            _reportViewer(state.pathParameters['reportId'], ReportsShell.sales),
          ),
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
        GoRoute(
          path: salesSettings,
          name: 'sales_settings',
          pageBuilder: (context, state) =>
              _transitionPage(state, const SalesSettingsPage()),
        ),
        GoRoute(
          path: salesPriceList,
          name: 'sales_price_list',
          pageBuilder: (context, state) =>
              _transitionPage(state, const SalesPriceListPage()),
        ),
      ],
    );
  }
}
