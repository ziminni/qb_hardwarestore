import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/views/login_page.dart';
import 'package:client/features/dashboard/view/admin_dashboard.dart';
import 'package:client/features/admin/views/admin_user_management_page.dart';
import 'package:client/features/dashboard/view/inventory_dashboard.dart';
import 'package:client/features/dashboard/view/pos_dashboard.dart';
import 'package:client/features/dashboard/view/sales_dashboard.dart';
import 'package:go_router/go_router.dart';

class AppRoutes {
  AppRoutes._();

  static const String login = '/login';
  static const String adminDashboard = '/admin/dashboard';
  static const String adminUserManagement = '/admin/users';
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
        if (location == adminUserManagement && auth.roleName != 'admin') {
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
