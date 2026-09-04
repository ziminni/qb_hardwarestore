import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/features/admin/viewmodels/admin_mock_data.dart';
import 'package:client/features/admin/widgets/admin_sales_chart.dart';
import 'package:flutter/material.dart';

class SalesMonitoringPage extends StatelessWidget {
  const SalesMonitoringPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminSkeletonLayout(
      title: 'Sales & POS Monitoring',
      subtitle: 'Review store sales and point-of-sale activity.',
      selectedNavigationIndex: 3,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Weekly sales',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          AdminSalesChart(
            values: AdminMockData.salesValues,
            labels: AdminMockData.salesLabels,
          ),
        ],
      ),
    );
  }
}
