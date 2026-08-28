import 'package:client/features/dashboard/widget/admin_dashboard_content.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:flutter/material.dart';

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const DashboardShell(
      title: 'Admin Dashboard',
      subtitle: 'Monitor today’s business performance and operations.',
      selectedNavigationIndex: 0,
      navigationItems: [
        DashboardNavigationItem('Overview', Icons.dashboard_outlined),
        DashboardNavigationItem(
          'User management',
          Icons.manage_accounts_outlined,
        ),
        DashboardNavigationItem('Inventory', Icons.inventory_2_outlined),
        DashboardNavigationItem('Sales & POS', Icons.point_of_sale_outlined),
        DashboardNavigationItem('Requisitions', Icons.receipt_long_outlined),
        DashboardNavigationItem('Reports', Icons.bar_chart_rounded),
        DashboardNavigationItem('Audit logs', Icons.history_rounded),
        DashboardNavigationItem('Settings', Icons.settings_outlined),
      ],
      child: AdminDashboardContent(),
    );
  }
}
