import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/features/dashboard/widget/inventory_dashboard_content.dart';
import 'package:flutter/material.dart';

/// The inventory team's dashboard page.
class InventoryDashboard extends StatelessWidget {
  const InventoryDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const InventorySkeletonLayout(
      title: 'Inventory Dashboard',
      subtitle: 'Track stock levels, movements, and replenishment needs.',
      selectedNavigationIndex: 0,
      child: InventoryDashboardContent(),
    );
  }
}
