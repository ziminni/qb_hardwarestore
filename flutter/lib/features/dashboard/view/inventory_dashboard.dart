import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/dashboard/widget/inventory_dashboard_content.dart';
import 'package:flutter/material.dart';

class InventoryDashboard extends StatelessWidget {
  const InventoryDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const DashboardShell(
      title: 'Inventory Dashboard',
      subtitle: 'Track stock levels, movements, and replenishment needs.',
      selectedNavigationIndex: 0,
      navigationItems: [
        DashboardNavigationItem('Overview', Icons.dashboard_outlined),
        DashboardNavigationItem('Products', Icons.inventory_2_outlined),
        DashboardNavigationItem('Categories', Icons.category_outlined),
        DashboardNavigationItem('Suppliers', Icons.local_shipping_outlined),
        DashboardNavigationItem('Stock movements', Icons.swap_vert_rounded),
        DashboardNavigationItem('Requisitions', Icons.receipt_long_outlined),
        DashboardNavigationItem('Reports', Icons.bar_chart_rounded),
      ],
      child: InventoryDashboardContent(),
    );
  }
}
