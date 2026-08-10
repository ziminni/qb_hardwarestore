import 'package:go_router/go_router.dart';

// auth
import 'package:client/features/auth/views/login_page.dart';

// dashboards
import 'package:client/features/dashboard/view/admin_dashboard.dart';
import 'package:client/features/dashboard/view/inventory_dashboard.dart';
import 'package:client/features/dashboard/view/pos_dashboard.dart';
import 'package:client/features/dashboard/view/sales_dashboard.dart';

class AppRoutes {
  // Authentication
  static const String login = "/login";

  // Dashboards
  static const String adminDashboard = "/admin/dashboard";
  static const String inventoryDashboard = "/inventory/dashboard";
  static const String posDashboard = "/pos/dashboard";
  static const String salesDashboard = "/sales/dashboard";

  static GoRouter createRouter() {
    return GoRouter(
      initialLocation: login,

      routes: [
        GoRoute(
          path: login,
          name: 'login',
          builder: (context, state) => const LoginPage(),
        ),

        // DASHBOARD
        GoRoute(
          path: adminDashboard,
          name: 'admin_dashboard',
          builder: (context, state) => const AdminDashboard(),
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