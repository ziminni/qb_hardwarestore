import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/features/dashboard/viewmodels/dashboard_mock_data.dart';
import 'package:client/features/dashboard/widget/admin_action_button.dart';
import 'package:client/features/dashboard/widget/admin_list_item.dart';
import 'package:client/features/dashboard/widget/admin_metric_card.dart';
import 'package:client/features/dashboard/widget/admin_section.dart';
import 'package:flutter/material.dart';

/// The administrator's dashboard page.
class AdminDashboard extends StatelessWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminSkeletonLayout(
      title: 'Admin Dashboard',
      subtitle: 'Monitor today’s business performance and operations.',
      selectedNavigationIndex: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: DashboardMockData.adminMetrics
                .map(
                  (metric) => SizedBox(
                    width: 190,
                    child: AdminMetricCard(
                      label: metric.label,
                      value: metric.value,
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Expanded(
                flex: 2,
                child: AdminSection(
                  title: 'Sales summary',
                  child: SizedBox(
                    height: 220,
                    child: Center(child: Text('Sales chart')),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AdminSection(
                  title: 'Quick actions',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: DashboardMockData.adminQuickActions
                        .map((label) => AdminActionButton(label: label))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AdminSection(
                  title: 'Recent activity',
                  actionLabel: 'View all',
                  child: Column(
                    children: DashboardMockData.adminRecentActivity
                        .map(
                          (item) => AdminListItem(
                            title: item.title,
                            subtitle: item.subtitle,
                            trailing: item.trailing,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AdminSection(
                  title: 'System alerts',
                  child: Column(
                    children: DashboardMockData.adminAlerts
                        .map(
                          (item) => AdminListItem(
                            title: item.title,
                            subtitle: item.subtitle,
                            trailing: item.trailing,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
