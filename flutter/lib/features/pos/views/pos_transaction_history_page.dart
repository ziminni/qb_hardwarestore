import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_transactions_content.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// POS-native transaction history (tab 1).
///
/// Reuses the global [InventorySalesViewmodel], the same data as the sales
/// transactions page, wrapped in the POS shell so the cashier stays in the POS
/// workflow. See decisions 03 + 04.
///
/// The list itself is [SalesTransactionsContent] (card S1): the three screens
/// that show transactions used to be three copies with three column sets and
/// three table styles. The cashier reads it without the Source column.
class PosTransactionHistoryPage extends StatefulWidget {
  const PosTransactionHistoryPage({super.key});

  @override
  State<PosTransactionHistoryPage> createState() =>
      _PosTransactionHistoryPageState();
}

class _PosTransactionHistoryPageState extends State<PosTransactionHistoryPage> {
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

    return DashboardShell(
      title: 'Transaction History',
      subtitle: 'Review completed, refunded, and voided sales.',
      selectedNavigationIndex: 1,
      navigationItems: posNavigationItems,
      onNavigationSelected: (i) => navigatePos(context, i),
      child: SalesTransactionsContent(
        role: SalesTransactionsRole.cashier,
        sales: viewmodel.sales,
        isLoading: viewmodel.isLoading,
        loadError: viewmodel.loadError,
        onRetry: viewmodel.load,
      ),
    );
  }
}
