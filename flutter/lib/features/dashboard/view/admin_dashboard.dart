import 'package:client/features/dashboard/widget/admin_dashboard_content.dart';
import 'package:client/features/admin/widgets/admin_navigation_items.dart';
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
      navigationItems: adminNavigationItems,
      child: AdminDashboardContent(),
    );
  }
}
