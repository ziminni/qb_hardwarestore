import 'package:client/core/layout/inventory_skeleton_layout.dart';
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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InventorySalesViewmodel>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<InventorySalesViewmodel>();

    return InventorySkeletonLayout(
      title: 'Sales',
      subtitle: 'Review inventory deducted through completed sales.',
      selectedNavigationIndex: 9,
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
