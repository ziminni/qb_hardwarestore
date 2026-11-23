import 'dart:async';

import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_transactions_content.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The stock manager's read-only view of what left the warehouse through sales.
///
/// The list is [SalesTransactionsContent] in its stock view (card S1): units out
/// is the emphasised number, and the money lives in the details sheet.
class InventorySalesPage extends StatefulWidget {
  const InventorySalesPage({super.key});
  @override
  State<InventorySalesPage> createState() => _InventorySalesPageState();
}

class _InventorySalesPageState extends State<InventorySalesPage> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<InventorySalesViewmodel>().load();
      _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
        if (mounted) {
          context.read<InventorySalesViewmodel>().load(silent: true);
        }
      });
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<InventorySalesViewmodel>();

    return InventorySkeletonLayout(
      title: 'Sales',
      subtitle:
          'Read-only log of goods sold off your shelves (units deducted per completed sale).',
      selectedNavigationIndex: AppDestinations.indexOf(
        'inventory.sales',
        AppAreas.inventory,
      ),
      // See the manager page: the list owns the scrolling, so it builds only the
      // rows on screen.
      scrollable: false,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: SalesTransactionsContent(
        role: SalesTransactionsRole.stockManager,
        sales: viewmodel.sales,
        isLoading: viewmodel.isLoading,
        loadError: viewmodel.loadError,
        onRetry: viewmodel.load,
      ),
    );
  }
}
