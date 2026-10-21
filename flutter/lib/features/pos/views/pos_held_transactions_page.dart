import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/held_cart.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/viewmodels/held_cart_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:client/features/sales/widgets/sales_records_table.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// POS-native held/parked transactions (tab 4).
///
/// A held cart is a basket the cashier parked mid-sale. Nothing has been
/// deducted and no money moved, so every row here is resumable until it is
/// either voided or completed. See decisions 03 (append-only tabs) and Phase 3
/// of the cashier workflow.
class PosHeldTransactionsPage extends StatefulWidget {
  const PosHeldTransactionsPage({super.key, this.viewmodel});

  /// Injectable for tests — same convention as [PosReceivablesPage].
  final HeldCartViewmodel? viewmodel;

  @override
  State<PosHeldTransactionsPage> createState() =>
      _PosHeldTransactionsPageState();
}

class _PosHeldTransactionsPageState extends State<PosHeldTransactionsPage> {
  late final HeldCartViewmodel _viewmodel = _resolveViewmodel();

  /// Only set when this page had to create its own queue.
  HeldCartViewmodel? _ownedViewmodel;

  /// Injected, else the app-level instance, else one of our own.
  ///
  /// The shared instance is what makes Resume work: the till is a different
  /// route, so the parked basket it must pick up is handed over through this
  /// viewmodel (see [HeldCartViewmodel.resumeCart]). The owned fallback only
  /// keeps a bare page (a widget test) rendering.
  HeldCartViewmodel _resolveViewmodel() {
    final injected = widget.viewmodel;
    if (injected != null) return injected;
    try {
      return context.read<HeldCartViewmodel>();
    } on ProviderNotFoundException {
      return _ownedViewmodel = HeldCartViewmodel();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _viewmodel.load();
    });
  }

  @override
  void dispose() {
    // Only dispose the one we own; an injected or shell-provided viewmodel
    // belongs to the caller / the shell.
    _ownedViewmodel?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<HeldCartViewmodel>.value(
      value: _viewmodel,
      child: const _PosHeldTransactionsView(),
    );
  }
}

class _PosHeldTransactionsView extends StatelessWidget {
  const _PosHeldTransactionsView();

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<HeldCartViewmodel>();
    final now = DateTime.now();

    return DashboardShell(
      title: 'Held Transactions',
      subtitle: 'Parked baskets waiting to be resumed or discarded.',
      selectedNavigationIndex: 4,
      navigationItems: posNavigationItems,
      onNavigationSelected: (i) => navigatePos(context, i),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (viewmodel.loadError != null)
            LiveLoadErrorBanner(
              message: viewmodel.loadError!,
              onRetry: viewmodel.load,
            ),
          if (viewmodel.isLoading && !viewmodel.hasCarts)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            SalesRecordsTable(
              columns: const ['Customer', 'Items', 'Held', 'Notes', 'Action'],
              emptyMessage: viewmodel.loadError != null
                  ? 'Held transactions could not be loaded.'
                  : 'No held transactions.',
              rows: viewmodel.carts
                  .map((cart) => _row(context, viewmodel, cart, now))
                  .toList(),
            ),
        ],
      ),
    );
  }

  List<Widget> _row(
    BuildContext context,
    HeldCartViewmodel viewmodel,
    HeldCart cart,
    DateTime now,
  ) {
    return <Widget>[
      Text(cart.customerLabel),
      Text('${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}'),
      Text(heldCartAgeLabel(cart.createdAt, now: now)),
      Text(cart.notes.isEmpty ? '—' : cart.notes),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            // A parked basket is only useful if it can be picked back up, so
            // Resume hands the basket to the till and returns there. Decision 03
            // keeps the cashier inside the POS shell for every step.
            //
            // The basket is recorded on the SHARED viewmodel before navigating:
            // the till is another route with its own state, so this hand-off is
            // the only thing that survives the hop.
            onPressed: () {
              viewmodel.resumeCart(cart);
              context.go(AppRoutes.posDashboard);
            },
            child: const Text('Resume'),
          ),
          TextButton(
            onPressed: () => _confirmVoid(context, viewmodel, cart),
            child: const Text('Void'),
          ),
        ],
      ),
    ];
  }
}

/// How long a basket has been parked, in the coarsest useful unit.
///
/// Deliberately not a precise timestamp: what a cashier needs to know is
/// "is this the one from ten minutes ago or from before lunch".
String heldCartAgeLabel(DateTime createdAt, {required DateTime now}) {
  final elapsed = now.difference(createdAt);
  if (elapsed.isNegative) return 'Just now';
  if (elapsed.inMinutes < 1) return 'Just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}m ago';
  if (elapsed.inHours < 24) return '${elapsed.inHours}h ago';
  return '${elapsed.inDays}d ago';
}

/// Voiding destroys a parked basket and its lines — there is no undo, so the
/// cashier names the customer before it happens.
Future<void> _confirmVoid(
  BuildContext context,
  HeldCartViewmodel viewmodel,
  HeldCart cart,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Void held transaction'),
      content: Text(
        'Discard the held basket for ${cart.customerLabel}? '
        'This cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text('Void'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  final ok = await viewmodel.voidCart(cart.id);
  if (!context.mounted) return;
  if (!ok) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          viewmodel.actionError ?? 'The held transaction could not be voided.',
        ),
      ),
    );
  }
}
