import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/features/admin/viewmodels/admin_mock_data.dart';
import 'package:client/features/admin/widgets/admin_report_filters.dart';
import 'package:flutter/material.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminSkeletonLayout(
      title: 'Reports',
      subtitle: 'Configure and generate administrative reports.',
      selectedNavigationIndex: 5,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Generate report',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          AdminReportFilters(reportTypes: AdminMockData.reportTypes),
          SizedBox(height: 24),
          SizedBox(
            height: 280,
            child: Center(child: Text('Generated report preview')),
          ),
        ],
      ),
    );
  }
}
