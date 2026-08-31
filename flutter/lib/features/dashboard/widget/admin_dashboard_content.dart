import 'package:client/features/dashboard/widget/mock_action.dart';
import 'package:client/features/dashboard/widget/mock_list_row.dart';
import 'package:client/features/dashboard/widget/mock_metric.dart';
import 'package:client/features/dashboard/widget/mock_section.dart';
import 'package:flutter/material.dart';

class AdminDashboardContent extends StatelessWidget {
  const AdminDashboardContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 190,
              child: MockMetric(label: 'Today sales', value: '₱ 0.00'),
            ),
            SizedBox(
              width: 190,
              child: MockMetric(label: 'Products', value: '0'),
            ),
            SizedBox(
              width: 190,
              child: MockMetric(label: 'Low stock', value: '0'),
            ),
            SizedBox(
              width: 190,
              child: MockMetric(label: 'Active users', value: '0'),
            ),
          ],
        ),
        SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: MockSection(
                title: 'Sales summary / chart placeholder',
                child: SizedBox(
                  height: 220,
                  child: Center(child: Text('[ CHART GOES HERE ]')),
                ),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: MockSection(
                title: 'Quick actions',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    MockAction(label: 'Create user'),
                    MockAction(label: 'Add product'),
                    MockAction(label: 'View reports'),
                    MockAction(label: 'Settings'),
                  ],
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MockSection(
                title: 'Recent activity',
                actionLabel: 'View all',
                child: Column(
                  children: [
                    MockListRow(
                      title: '[ Activity item ]',
                      subtitle: '[ User ] · [ Time ]',
                    ),
                    Divider(),
                    MockListRow(
                      title: '[ Activity item ]',
                      subtitle: '[ User ] · [ Time ]',
                    ),
                    Divider(),
                    MockListRow(
                      title: '[ Activity item ]',
                      subtitle: '[ User ] · [ Time ]',
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: MockSection(
                title: 'System alerts',
                child: Column(
                  children: [
                    MockListRow(
                      title: '[ Alert ]',
                      subtitle: '[ Description ]',
                      trailing: '[ Status ]',
                    ),
                    Divider(),
                    MockListRow(
                      title: '[ Alert ]',
                      subtitle: '[ Description ]',
                      trailing: '[ Status ]',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
