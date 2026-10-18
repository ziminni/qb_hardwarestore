import 'package:client/core/constants/app_durations.dart';
import 'package:client/features/admin/views/admin_user_management_page.dart';
import 'package:client/features/admin/views/audit_logs_page.dart';
import 'package:client/features/admin/views/inventory_monitoring_page.dart';
import 'package:client/features/admin/views/reports_page.dart';
import 'package:client/features/admin/views/requisitions_page.dart';
import 'package:client/features/admin/views/sales_monitoring_page.dart';
import 'package:client/features/admin/views/settings_page.dart';
import 'package:client/features/categories/views/categories_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/views/login_page.dart';
import 'package:client/features/auth/views/unsupported_role_page.dart';
import 'package:client/features/dashboard/views/admin_dashboard.dart';
import 'package:client/features/dashboard/views/inventory_dashboard.dart';
import 'package:client/features/pos/views/pos_transaction_page.dart';
import 'package:client/features/pos/views/material_release_page.dart';
import 'package:client/features/sales/views/sales_dashboard_page.dart';
import 'package:client/features/sales/views/sales_orders_page.dart';
import 'package:client/features/sales/views/sales_quotations_page.dart';
import 'package:client/features/sales/views/sales_receivables_page.dart';
import 'package:client/features/sales/views/sales_returns_page.dart';
import 'package:client/features/sales/views/sales_transactions_page.dart';
import 'package:client/features/inventory/views/inventory_stock_movements_page.dart';
import 'package:client/features/inventory/views/inventory_low_stock_page.dart';
import 'package:client/features/inventory/views/inventory_stock_page.dart';
import 'package:client/features/products/views/products_page.dart';
import 'package:client/features/suppliers/views/purchases_page.dart';
import 'package:client/features/suppliers/views/suppliers_page.dart';
import 'package:client/features/sales/views/inventory_returns_page.dart';
import 'package:client/features/sales/views/inventory_sales_page.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppRoutes {
  AppRoutes._();

  static const String login = '/login';

  /// Where an authenticated account with no POS dashboard is sent.
  /// See [UnsupportedRolePage] and decision 04.
  static const String unsupportedRole = '/unsupported-role';
  static const String adminDashboard = '/admin/dashboard';
  static const String adminUserManagement = '/admin/users';
  static const String adminInventory = '/admin/inventory';
  static const String adminSales = '/admin/sales';
  static const String adminRequisitions = '/admin/requisitions';
  static const String adminReports = '/admin/reports';
  static const String adminAuditLogs = '/admin/audit-logs';
  static const String adminSettings = '/admin/settings';
  static const String inventoryDashboard = '/inventory/dashboard';
  static const String inventoryProducts = '/inventory/products';
  static const String inventoryCategories = '/inventory/categories';
  static const String inventoryStock = '/inventory/stock';
  static const String inventoryStockMovements = '/inventory/stock-movements';
  static const String inventoryLowStock = '/inventory/low-stock';
  static const String inventoryPurchases = '/inventory/purchases';
  static const String inventorySuppliers = '/inventory/suppliers';
  static const String inventorySales = '/inventory/sales';
  static const String inventoryReturns = '/inventory/returns';
  static const String posDashboard = '/pos/dashboard';
  static const String posRelease = '/pos/release';
  static const String salesDashboard = '/sales/dashboard';
  static const String salesTransactions = '/sales/transactions';
  static const String salesQuotations = '/sales/quotations';
  static const String salesOrders = '/sales/orders';
  static const String salesReceivables = '/sales/receivables';
  static const String salesReturns = '/sales/returns';

  /// The pure routing decision: where a request to [location] should go, or null
  /// to stay.
  ///
  /// Extracted from the router's `redirect` closure so the role rules are
  /// testable **without rendering a dashboard**. Every dashboard is built on the
  /// same skeleton, whose existing layout assertions fire under a widget test,
  /// so a routing test that rendered one would fail for a reason that has
  /// nothing to do with routing.
  static String? redirectFor({
    required bool isAuthenticated,
    required String? role,
    required String location,
  }) {
    final isLogin = location == login;
    final isUnsupported = location == unsupportedRole;

    if (!isAuthenticated) return isLogin ? null : login;

    final dashboard = dashboardForRole(role);
    if (dashboard == null) {
      // Decision 04: an unmapped or role-less account gets an explicit screen,
      // never a silent bounce to `/login` while apparently signed in. Returning
      // null when already there is what stops this from looping.
      return isUnsupported ? null : unsupportedRole;
    }
    if (isLogin || isUnsupported) return dashboard;
    if (location.startsWith('/admin/') && role != 'admin') {
      // Decisions 16 and 20: the Store Manager (client role 'sales') is the
      // month-end actor and the requisition approver, and IsManagerRole admits
      // them server-side — the fence opens for the reports screen and the
      // approve queue only. User management, audit logs and settings stay
      // admin-only; Cashier ('pos') and Stock Manager ('inventory') still bounce.
      if ((location == adminReports || location == adminRequisitions) &&
          role == 'sales') {
        return null;
      }
      return dashboard;
    }
    if (location.startsWith('/inventory/') && role != 'inventory') {
      return dashboard;
    }
    if (location.startsWith('/sales/') && role != 'sales') return dashboard;

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
      'admin' => adminDashboard,
      'inventory' => inventoryDashboard,
      'pos' => posDashboard,
      'sales' => salesDashboard,
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
      transitionDuration: AppDurations.normal,
      reverseTransitionDuration: AppDurations.normal,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (MediaQuery.disableAnimationsOf(context)) return child;

        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );

        return FadeTransition(
          opacity: curvedAnimation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.015, 0),
              end: Offset.zero,
            ).animate(curvedAnimation),
            child: child,
          ),
        );
      },
    );
  }

  static GoRouter createRouter(AuthViewmodel auth) {
    return GoRouter(
      initialLocation: login,
      refreshListenable: auth,
      redirect: (context, state) => redirectFor(
        isAuthenticated: auth.isAuthenticated,
        role: auth.roleName,
        location: state.matchedLocation,
      ),
      routes: [
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
          path: adminDashboard,
          name: 'admin_dashboard',
          pageBuilder: (context, state) =>
              _transitionPage(state, const AdminDashboard()),
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
          path: adminRequisitions,
          name: 'admin_requisitions',
          pageBuilder: (context, state) =>
              _transitionPage(state, const RequisitionsPage()),
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
          path: inventoryReturns,
          name: 'inventory_returns',
          pageBuilder: (context, state) =>
              _transitionPage(state, const InventoryReturnsPage()),
        ),
        GoRoute(
          path: posDashboard,
          name: 'pos_dashboard',
          pageBuilder: (context, state) =>
              _transitionPage(state, const PosTransactionPage()),
        ),
        GoRoute(
          path: posRelease,
          name: 'pos_release',
          pageBuilder: (context, state) =>
              _transitionPage(state, const MaterialReleasePage()),
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
      ],
    );
  }
}
