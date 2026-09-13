import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/features/dashboard/widget/inventory_dashboard_content.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// The inventory team's dashboard page.
class InventoryDashboard extends StatelessWidget {
  const InventoryDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return InventorySkeletonLayout(
      title: 'Inventory Dashboard',
      subtitle: 'Track stock levels, movements, and replenishment needs.',
      selectedNavigationIndex: 0,
      onNavigationSelected: (index) {
        if (index == 0) context.go(AppRoutes.inventoryDashboard);
        if (index == 1) context.go(AppRoutes.inventoryProducts);
      },
      child: const InventoryDashboardContent(),
    );
  }
}
