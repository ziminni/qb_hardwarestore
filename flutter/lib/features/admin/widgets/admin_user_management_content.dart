import 'package:client/features/admin/widgets/admin_user_filters.dart';
import 'package:client/features/admin/widgets/admin_user_action_button.dart';
import 'package:client/features/admin/widgets/admin_user_metric_card.dart';
import 'package:client/features/admin/widgets/admin_user_section.dart';
import 'package:client/features/admin/widgets/admin_user_table.dart';
import 'package:flutter/material.dart';

class AdminUserManagementContent extends StatelessWidget {
  const AdminUserManagementContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Staff accounts',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            AdminUserActionButton(
              label: 'Create account',
              icon: Icons.person_add_outlined,
            ),
          ],
        ),
        SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 190,
              child: AdminUserMetricCard(label: 'Total accounts', value: '0'),
            ),
            SizedBox(
              width: 190,
              child: AdminUserMetricCard(label: 'Active accounts', value: '0'),
            ),
            SizedBox(
              width: 190,
              child: AdminUserMetricCard(
                label: 'Inactive accounts',
                value: '0',
              ),
            ),
            SizedBox(
              width: 190,
              child: AdminUserMetricCard(label: 'Roles assigned', value: '0'),
            ),
          ],
        ),
        SizedBox(height: 16),
        AdminUserSection(
          title: 'Search and filters',
          child: AdminUserFilters(),
        ),
        SizedBox(height: 16),
        AdminUserSection(
          title: 'User accounts',
          actionLabel: 'Export',
          child: AdminUserTable(),
        ),
      ],
    );
  }
}
