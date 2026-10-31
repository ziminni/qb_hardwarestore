import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_receivables_content.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// POS-native receivables (tab 3), the cashier's Record payment screen.
///
/// A shell only (card S2): the same [SalesReceivablesContent] as the Store
/// Manager's Receivables screen, wrapped in the POS shell so the cashier stays
/// in the POS workflow. Reuses [SalesReceivablesViewmodel] - one dataset, one
/// payment dialog, one error banner.
class PosReceivablesPage extends StatelessWidget {
  const PosReceivablesPage({super.key, this.viewmodel});

  /// Injected by tests so a state can be rendered WITHOUT a server; in
  /// production the page builds its own viewmodel and loads it.
  final SalesReceivablesViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => (viewmodel ?? SalesReceivablesViewmodel())..load(),
      child: const _PosReceivablesView(),
    );
  }
}

class _PosReceivablesView extends StatelessWidget {
  const _PosReceivablesView();

  @override
  Widget build(BuildContext context) {
    return DashboardShell(
      title: 'Record Payment',
      subtitle: 'Track unpaid balances and record customer payments.',
      selectedNavigationIndex: 3,
      navigationItems: posNavigationItems,
      onNavigationSelected: (i) => navigatePos(context, i),
      // The list owns the scrolling, so it builds only the rows on screen.
      scrollable: false,
      child: const SalesReceivablesContent(),
    );
  }
}
