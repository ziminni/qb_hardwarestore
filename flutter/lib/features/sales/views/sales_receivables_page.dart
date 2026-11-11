import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/features/sales/viewmodels/cheque_queue_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_receivables_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_receivables_content.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The receivables screen, on real data.
///
/// A shell only (card S2): the list, the totals, the filters and the payment
/// dialog all live in [SalesReceivablesContent], which the cashier's Record
/// payment screen shows too. The two screens used to be two copies of the same
/// page, and the copies drifted.
class SalesReceivablesPage extends StatelessWidget {
  const SalesReceivablesPage({super.key, this.viewmodel, this.chequeViewmodel});

  /// Injected by tests so a state can be rendered WITHOUT a server; in
  /// production the page builds its own viewmodel and loads it.
  final SalesReceivablesViewmodel? viewmodel;

  /// The manager's cheque queue (F5). Provided here and only here: the cashier's
  /// Record payment shell shows the same body without it, so the decision queue
  /// is unreachable for a cashier by construction rather than by a fence inside
  /// the widget.
  final ChequeQueueViewmodel? chequeViewmodel;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => (viewmodel ?? SalesReceivablesViewmodel())..load(),
        ),
        // Lazily created, so a screen that never opens the Cheques tab never
        // asks the server for the queue (and a 403 cannot greet the ledger).
        ChangeNotifierProvider(
          create: (_) => (chequeViewmodel ?? ChequeQueueViewmodel())..load(),
        ),
      ],
      child: const _ReceivablesView(),
    );
  }
}

class _ReceivablesView extends StatelessWidget {
  const _ReceivablesView();

  @override
  Widget build(BuildContext context) {
    return SalesSkeletonLayout(
      title: 'Receivables',
      subtitle: 'Track unpaid, partial, and overdue customer balances.',
      selectedNavigationIndex: 4,
      // The list owns the scrolling, so it builds only the rows on screen.
      scrollable: false,
      onNavigationSelected: (index) => navigateSales(context, index),
      // The manager may also decide cheques: the tab is enabled on this screen
      // alone (decision 18 - deciding a cheque is receivables work).
      child: const SalesReceivablesContent(showCheques: true),
    );
  }
}
