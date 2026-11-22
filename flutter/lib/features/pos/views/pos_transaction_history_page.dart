import 'dart:async';

import 'package:client/core/constants/app_colors.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/widgets/pos_attach_or_dialog.dart';
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

    return DashboardShell(
      title: 'Transaction History',
      subtitle:
          'Review completed, exchanged, refunded, and voided sales — or attach an OR.',
      selectedNavigationIndex: 1,
      navigationItems: posNavigationItems,
      onNavigationSelected: (i) => navigatePos(context, i),
      actions: [
        Tooltip(
          message: 'Tag a past sale with the paper OR invoice no.',
          child: TextButton.icon(
            key: const ValueKey('history-attach-or-button'),
            onPressed: () async {
              await openAttachOrDialog(context);
              if (context.mounted) {
                unawaited(viewmodel.load(silent: true));
              }
            },
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              minimumSize: const Size(44, 40),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: const BorderSide(color: AppColors.border),
              ),
            ),
            icon: const Icon(Icons.receipt_long_outlined, size: 18),
            label: const Text('Attach OR'),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Refresh transactions',
          onPressed: viewmodel.isLoading ? null : viewmodel.load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      // See the manager page: the list owns the scrolling, so it builds only the
      // rows on screen.
      scrollable: false,
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
