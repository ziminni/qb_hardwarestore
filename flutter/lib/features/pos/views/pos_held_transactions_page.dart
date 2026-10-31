import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/held_cart.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/viewmodels/held_cart_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_held_cart_card.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/metric_grid.dart';
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

  /// A card never gets narrower than this: below it the money and the two
  /// actions start competing for the same line.
  static const double _minCardWidth = 300;

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<HeldCartViewmodel>();
    // Read once per build: an age computed from a moving clock could change
    // halfway down the list.
    final now = DateTime.now();
    final failure = viewmodel.loadError;
    // A first load that failed is ONE banner. Nothing goes under it: an empty
    // state there would state that no basket is parked, which is the one fact a
    // failed read has not established, and a cashier would re-ring a basket
    // that is still held.
    final firstLoadFailed = failure != null && !viewmodel.hasCarts;
    final carts = _newestFirst(viewmodel.carts);

    return DashboardShell(
      title: 'Held Transactions',
      subtitle: 'Parked baskets waiting to be resumed or discarded.',
      selectedNavigationIndex: DashboardShell.heldTransactionsIndex,
      navigationItems: posNavigationItems,
      onNavigationSelected: (i) => navigatePos(context, i),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A refresh that fails keeps the baskets it already had: they are
          // still parked on the server, so they stay on screen under the banner.
          if (failure != null) ...[
            ErrorBanner(message: failure, onRetry: viewmodel.load),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (viewmodel.isLoading && !viewmodel.hasCarts)
            const AppPanel(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 32),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (firstLoadFailed)
            const SizedBox.shrink()
          else if (carts.isEmpty)
            AppPanel(
              child: EmptyState(
                icon: Icons.pause_circle_outline,
                message: 'No held transactions.',
                actionLabel: 'Go to the till',
                onAction: () => context.go(AppRoutes.posDashboard),
              ),
            )
          else
            // A wrapping grid of cards, not a table: a parked basket carries
            // four short facts and two actions, and the same card works on a
            // phone-width window. MetricGrid supplies the column maths so the
            // row fills the width instead of leaving a ragged half-empty row.
            MetricGrid(
              minTileWidth: _minCardWidth,
              children: [
                for (final cart in carts)
                  PosHeldCartCard(
                    key: ValueKey('held-cart-${cart.id}'),
                    cart: cart,
                    ageLabel: heldCartAgeLabel(cart.createdAt, now: now),
                    onResume: () => _resume(context, viewmodel, cart),
                    onVoid: () => _confirmVoid(context, viewmodel, cart),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  /// The basket parked a minute ago is the one the cashier came back for, so
  /// the queue reads newest first regardless of the order the server sent.
  static List<HeldCart> _newestFirst(List<HeldCart> carts) {
    final sorted = [...carts]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return sorted;
  }

  /// A parked basket is only useful if it can be picked back up, so Resume
  /// hands the basket to the till and returns there (decision 03 keeps the
  /// cashier inside the POS shell for every step).
  ///
  /// The basket is recorded on the SHARED viewmodel before navigating: the till
  /// is another route with its own state, so this hand-off is the only thing
  /// that survives the hop.
  void _resume(
    BuildContext context,
    HeldCartViewmodel viewmodel,
    HeldCart cart,
  ) {
    viewmodel.resumeCart(cart);
    context.go(AppRoutes.posDashboard);
  }
}

/// How long a basket has been parked, in the coarsest useful unit.
///
/// Deliberately not a precise timestamp: what a cashier needs to know is
/// "is this the one from ten minutes ago or from before lunch". Lower case
/// because the card reads "Held 12 min ago".
String heldCartAgeLabel(DateTime createdAt, {required DateTime now}) {
  final elapsed = now.difference(createdAt);
  if (elapsed.isNegative) return 'just now';
  if (elapsed.inMinutes < 1) return 'just now';
  if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
  if (elapsed.inHours < 24) {
    return '${elapsed.inHours} hr${elapsed.inHours == 1 ? '' : 's'} ago';
  }
  return '${elapsed.inDays} day${elapsed.inDays == 1 ? '' : 's'} ago';
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
