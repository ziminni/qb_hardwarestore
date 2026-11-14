import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_transactions_content.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SalesTransactionsPage extends StatefulWidget {
  const SalesTransactionsPage({super.key});
  @override
  State<SalesTransactionsPage> createState() => _SalesTransactionsPageState();
}

class _SalesTransactionsPageState extends State<SalesTransactionsPage> {
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

    return SalesSkeletonLayout(
      title: 'Sales Transactions',
      subtitle: 'Review completed, refunded, and voided sales.',
      selectedNavigationIndex: 1,
      // The list scrolls and builds inside its own bounded slot: the service can
      // load 40 pages, and a page scroll view would lay every row out at once.
      scrollable: false,
      onNavigationSelected: (index) => navigateSales(context, index),
      child: SalesTransactionsContent(
        role: SalesTransactionsRole.storeManager,
        sales: viewmodel.sales,
        isLoading: viewmodel.isLoading,
        loadError: viewmodel.loadError,
        onRetry: viewmodel.load,
      ),
    );
  }
}
