import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/features/admin/viewmodels/admin_mock_data.dart';
import 'package:client/features/admin/widgets/admin_inventory_summary.dart';
import 'package:flutter/material.dart';

class InventoryMonitoringPage extends StatelessWidget {
  const InventoryMonitoringPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminSkeletonLayout(
      title: 'Inventory Monitoring',
      subtitle: 'Monitor product availability and inventory health.',
      selectedNavigationIndex: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Inventory overview',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          AdminInventorySummary(metrics: AdminMockData.inventoryMetrics),
        ],
      ),
    );
  }
}
