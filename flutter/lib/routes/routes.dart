import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/views/login_page.dart';
import 'package:client/features/admin/views/admin_user_management_page.dart';
import 'package:client/features/admin/views/audit_logs_page.dart';
import 'package:client/features/admin/views/inventory_monitoring_page.dart';
import 'package:client/features/admin/views/reports_page.dart';
import 'package:client/features/admin/views/requisitions_page.dart';
import 'package:client/features/admin/views/sales_monitoring_page.dart';
import 'package:client/features/admin/views/settings_page.dart';
import 'package:client/features/dashboard/views/admin_dashboard.dart';
import 'package:client/features/dashboard/views/inventory_dashboard.dart';
import 'package:client/features/dashboard/views/pos_dashboard.dart';
import 'package:client/features/dashboard/views/sales_dashboard.dart';
import 'package:go_router/go_router.dart';

class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String adminDashboard = '/admin/dashboard';
  static const String adminUserManagement = '/admin/users';
  static const String adminInventory = '/admin/inventory';
  static const String adminSales = '/admin/sales';
  static const String adminRequisitions = '/admin/requisitions';
  static const String adminReports = '/admin/reports';
  static const String adminAuditLogs = '/admin/audit-logs';
  static const String adminSettings = '/admin/settings';
  static const String inventoryDashboard = '/inventory/dashboard';
  static const String posDashboard = '/pos/dashboard';
  static const String salesDashboard = '/sales/dashboard';

  static String? dashboardForRole(String? role) {
    return switch (role) {
      'admin' => adminDashboard,
      'inventory' => inventoryDashboard,
      'pos' => posDashboard,
      'sales' => salesDashboard,
      _ => null,
    };
  }

  static GoRouter createRouter(AuthViewmodel auth) {
    return GoRouter(
      initialLocation: login,
      refreshListenable: auth,
      redirect: (context, state) {
        final location = state.matchedLocation;
        final isLogin = location == login;

        if (!auth.isAuthenticated) return isLogin ? null : login;

        final dashboard = dashboardForRole(auth.roleName);
        if (dashboard == null) return isLogin ? null : login;
        if (isLogin) return dashboard;
        if (location.startsWith('/admin/') && auth.roleName != 'admin') {
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
      },
      routes: [
        GoRoute(
          path: login,
          name: 'login',
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: adminDashboard,
          name: 'admin_dashboard',
          builder: (context, state) => const AdminDashboard(),
        ),
        GoRoute(
          path: adminUserManagement,
          name: 'admin_user_management',
          builder: (context, state) => const AdminUserManagementPage(),
        ),
        GoRoute(
          path: adminInventory,
          name: 'admin_inventory',
          builder: (context, state) => const InventoryMonitoringPage(),
        ),
        GoRoute(
          path: adminSales,
          name: 'admin_sales',
          builder: (context, state) => const SalesMonitoringPage(),
        ),
        GoRoute(
          path: adminRequisitions,
          name: 'admin_requisitions',
          builder: (context, state) => const RequisitionsPage(),
        ),
        GoRoute(
          path: adminReports,
          name: 'admin_reports',
          builder: (context, state) => const ReportsPage(),
        ),
        GoRoute(
          path: adminAuditLogs,
          name: 'admin_audit_logs',
          builder: (context, state) => const AuditLogsPage(),
        ),
        GoRoute(
          path: adminSettings,
          name: 'admin_settings',
          builder: (context, state) => const SettingsPage(),
        ),
        GoRoute(
          path: inventoryDashboard,
          name: 'inventory_dashboard',
          builder: (context, state) => const InventoryDashboard(),
        ),
        GoRoute(
          path: posDashboard,
          name: 'pos_dashboard',
          builder: (context, state) => const POSDashboard(),
        ),
        GoRoute(
          path: salesDashboard,
          name: 'sales_dashboard',
          builder: (context, state) => const SalesDashboard(),
        ),
      ],
    );
  }
}
