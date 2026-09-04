import 'package:client/features/admin/widgets/admin_navigation_items.dart';
import 'package:client/features/admin/widgets/admin_user_management_content.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:flutter/material.dart';

class AdminUserManagementPage extends StatelessWidget {
  const AdminUserManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const DashboardShell(
      title: 'User Management',
      subtitle: 'Mock layout for viewing and managing staff accounts.',
      selectedNavigationIndex: 1,
      navigationItems: adminNavigationItems,
      child: AdminUserManagementContent(),
    );
  }
}
