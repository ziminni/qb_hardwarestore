import 'dart:async';

import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/widgets/pos_attach_or_dialog.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_transactions_content.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The till's OR-tagged tab.
///
/// The cashier comes back from the counter with a stack of paper ORs and has to
/// find the sale each one belongs to. Transaction history lists everything;
/// this tab asks the question the stack actually poses — "which slips have no OR
/// number yet?" — and puts the Attach action on those rows.
///
/// Same data and same list as [PosTransactionHistoryPage]: it reads the shared
/// [InventorySalesViewmodel] and renders [SalesTransactionsContent] with the
/// cashier's columns, adding only the OR filter chips and the row action.
class PosOrTaggedPage extends StatefulWidget {
  const PosOrTaggedPage({super.key});

  @override
  State<PosOrTaggedPage> createState() => _PosOrTaggedPageState();
}

class _PosOrTaggedPageState extends State<PosOrTaggedPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<InventorySalesViewmodel>().load();
    });
  }

  /// The dialog asks for the OS number itself, so the row it was opened from
  /// does not travel into it; the list is reloaded afterwards because the
  /// tagging happens on the server.
  Future<void> _attachOr() async {
    await openAttachOrDialog(context);
    if (!mounted) return;
    unawaited(context.read<InventorySalesViewmodel>().load(silent: true));
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<InventorySalesViewmodel>();

    return DashboardShell(
      title: 'OR-tagged',
      subtitle:
          'Tag past order slips with the paper OR number, and see which slips '
          'are already tagged.',
      selectedNavigationIndex: 2,
      navigationItems: posNavigationItems,
      onNavigationSelected: (i) => navigatePos(context, i),
      actions: [
        IconButton(
          tooltip: 'Refresh transactions',
          onPressed: viewmodel.isLoading ? null : viewmodel.load,
          icon: const Icon(Icons.refresh_rounded),
        ),
      ],
      // The list owns the scrolling, as on the history tab.
      scrollable: false,
      child: SalesTransactionsContent(
        role: SalesTransactionsRole.cashier,
        sales: viewmodel.sales,
        isLoading: viewmodel.isLoading,
        loadError: viewmodel.loadError,
        onRetry: viewmodel.load,
        orTracking: true,
        onAttachOr: _attachOr,
      ),
    );
  }
}
