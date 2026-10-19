import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/features/dashboard/widget/inventory_dashboard_content.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:provider/provider.dart';

/// The inventory team's dashboard page.
class InventoryDashboard extends StatefulWidget {
  const InventoryDashboard({super.key});

  @override
  State<InventoryDashboard> createState() => _InventoryDashboardState();
}

class _InventoryDashboardState extends State<InventoryDashboard> {
  @override
  void initState() {
    super.initState();
    // The 6C fix pass proved an unwired page silently shows bundled fixtures
    // (the till sold at mock prices). The dashboard loads on open for the
    // same reason.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InventoryViewmodel>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return InventorySkeletonLayout(
      title: 'Inventory Dashboard',
      subtitle: 'Track stock levels, movements, and replenishment needs.',
      selectedNavigationIndex: 0,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: const InventoryDashboardContent(),
    );
  }
}
