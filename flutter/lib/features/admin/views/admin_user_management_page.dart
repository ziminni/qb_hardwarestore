import 'package:client/features/admin/widgets/admin_user_management_content.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:flutter/material.dart';

class AdminUserManagementPage extends StatelessWidget {
  const AdminUserManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminSkeletonLayout(
      title: 'User Management',
      subtitle: 'Mock layout for viewing and managing staff accounts.',
      selectedNavigationIndex: 1,
      child: AdminUserManagementContent(),
    );
  }
}
