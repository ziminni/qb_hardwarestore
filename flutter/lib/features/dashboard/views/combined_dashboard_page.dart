import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/navigation/merged_sidebar.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/dashboard/widget/admin_needs_attention_panel.dart';
import 'package:client/features/dashboard/widget/inventory_dashboard_content.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/held_cart_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_dashboard_alerts_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_needs_you_tile.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/app_shell.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/section_heading.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Where a merged account lands (Phase 2 F4, decision 24): one page carrying
/// every assigned area's "needs you" tiles, in heading order.
///
/// Each section loads and fails on its own: a failed read shows its own
/// [ErrorBanner] with a retry, and the sections that succeeded keep their real
/// counts rather than a shared banner hiding every number behind one retry.
/// A single-area account never reaches this page — its own dashboard renders
/// first (`AppRoutes.redirectFor`), so merged-only state belongs here, not in
/// the single-role screens.
class CombinedDashboardPage extends StatelessWidget {
  const CombinedDashboardPage({
    super.key,
    this.shiftViewmodel,
    this.salesAlertsViewmodel,
  });

  /// Injected by tests so the Till section can be rendered WITHOUT a server;
  /// in production the section builds its own, like every screen-scoped
  /// viewmodel in this app (see [SalesDashboardPage]).
  final ShiftViewmodel? shiftViewmodel;
  final SalesDashboardAlertsViewmodel? salesAlertsViewmodel;

  @override
  Widget build(BuildContext context) {
    final areas = MergedSidebar.heldAreas(
      context.watch<AuthViewmodel>().assignedAreas,
    );
    return AppShell(
      title: 'Needs you',
      subtitle: 'What is waiting for you across every area you hold.',
      sections: const [],
      selectedIndex: -1,
      selectedId: MergedSidebar.combinedDashboardId,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final area in MergedSidebar.headingOrder)
            if (areas.contains(area)) ...[
              if (area != MergedSidebar.headingOrder.first)
                const SizedBox(height: AppSpacing.xl),
              SectionHeading(title: MergedSidebar.areaHeadings[area]!),
              _sectionFor(area),
            ],
        ],
      ),
    );
  }

  Widget _sectionFor(String area) => switch (area) {
    'pos' => _TillSection(viewmodel: shiftViewmodel),
    'sales' => _SalesSection(viewmodel: salesAlertsViewmodel),
    'inventory' => const _StockSection(),
    'admin' => const _AdminSection(),
    _ => const SizedBox.shrink(),
  };
}

class _TillSection extends StatefulWidget {
  const _TillSection({this.viewmodel});

  final ShiftViewmodel? viewmodel;

  @override
  State<_TillSection> createState() => _TillSectionState();
}

class _TillSectionState extends State<_TillSection> {
  /// Page-scoped, like [ShiftViewmodel]'s other dashboard caller
  /// (`PosTransactionPage`): a failed current-shift read leaves
  /// [ShiftViewmodel.currentShift] untouched, so "unknown" is never mistaken
  /// for "no shift" — that distinction lives in the viewmodel, not here.
  late final ShiftViewmodel _shift = widget.viewmodel ?? ShiftViewmodel();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _shift.loadCurrent();
      final carts = context.read<HeldCartViewmodel>();
      if (!carts.hasCarts && !carts.isLoading) carts.load();
    });
  }

  void _retryAll() {
    _shift.loadCurrent();
    context.read<HeldCartViewmodel>().load();
  }

  @override
  Widget build(BuildContext context) {
    final carts = context.watch<HeldCartViewmodel>();
    return ListenableBuilder(
      listenable: _shift,
      builder: (context, _) {
        final failure = carts.loadError ?? _shift.currentShiftError;
        final shiftLabel = _shift.currentShiftError != null
            ? 'Not loaded'
            : _shift.hasOpenShift
            ? 'Open'
            : 'No open shift';
        return _buildTill(context, carts, failure, shiftLabel);
      },
    );
  }

  Widget _buildTill(
    BuildContext context,
    HeldCartViewmodel carts,
    String? failure,
    String shiftLabel,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (failure != null) ...[
          ErrorBanner(message: failure, onRetry: _retryAll),
          const SizedBox(height: AppSpacing.md),
        ],
        MetricGrid(
          children: [
            SalesNeedsYouTile(
              key: const ValueKey('combinedDashboard.needsYou.heldCarts'),
              label: 'Held transactions',
              value: carts.loadError != null
                  ? 'Not loaded'
                  : formatCount(carts.carts.length),
              caption: 'Parked baskets',
              icon: Icons.pause_circle_outline,
              onTap: () => context.go(AppRoutes.posHeld),
            ),
            SalesNeedsYouTile(
              key: const ValueKey('combinedDashboard.needsYou.shift'),
              label: 'Shift',
              value: shiftLabel,
              caption: 'Open or close your drawer',
              icon: Icons.access_time,
              onTap: () => context.go(AppRoutes.posShifts),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    // A viewmodel the page injected belongs to the caller that created it; the
    // one built here is this section's own.
    if (widget.viewmodel == null) _shift.dispose();
    super.dispose();
  }
}

class _SalesSection extends StatefulWidget {
  const _SalesSection({this.viewmodel});

  final SalesDashboardAlertsViewmodel? viewmodel;

  @override
  State<_SalesSection> createState() => _SalesSectionState();
}

class _SalesSectionState extends State<_SalesSection> {
  late final SalesDashboardAlertsViewmodel _alerts =
      widget.viewmodel ?? SalesDashboardAlertsViewmodel();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _alerts.load();
    });
  }

  @override
  void dispose() {
    if (widget.viewmodel == null) _alerts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _alerts,
      builder: (context, _) {
        final failure = _alerts.loadError;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (failure != null) ...[
              ErrorBanner(message: failure, onRetry: _alerts.load),
              const SizedBox(height: AppSpacing.md),
            ],
            MetricGrid(
              children: [
                SalesNeedsYouTile(
                  key: const ValueKey('combinedDashboard.needsYou.receivables'),
                  label: 'Overdue receivables',
                  value: _alerts.overdueReceivables == null
                      ? 'Not loaded'
                      : formatCount(_alerts.overdueReceivables!),
                  caption: 'Customers past their due date',
                  icon: Icons.account_balance_wallet_outlined,
                  onTap: () => context.go(AppRoutes.salesReceivables),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _StockSection extends StatefulWidget {
  const _StockSection();

  @override
  State<_StockSection> createState() => _StockSectionState();
}

class _StockSectionState extends State<_StockSection> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final inventory = context.read<InventoryViewmodel>();
      if (!inventory.hasLoaded) inventory.load();
      final purchases = context.read<SuppliersPurchasesViewmodel>();
      if (purchases.purchases.isEmpty && !purchases.isLoading) {
        purchases.load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    final purchases = context.watch<SuppliersPurchasesViewmodel>();
    final failure = inventory.loadError;

    if ((inventory.isLoading || !inventory.hasLoaded) &&
        inventory.products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (failure != null && inventory.products.isEmpty) {
      return ErrorBanner(message: failure, onRetry: inventory.load);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (failure != null) ...[
          ErrorBanner(message: failure, onRetry: inventory.load),
          const SizedBox(height: AppSpacing.md),
        ],
        buildInventoryRestockPanel(context, inventory),
        const SizedBox(height: AppSpacing.lg),
        buildInventoryWaitingPanel(context, purchases),
      ],
    );
  }
}

class _AdminSection extends StatelessWidget {
  const _AdminSection();

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    final stockReady = inventory.hasLoaded && inventory.loadError == null;
    final unresolvedAlerts = inventory.alerts
        .where((alert) => !alert.isResolved)
        .length;

    return AdminNeedsAttentionPanel(
      items: [
        // Only when the alert feed answered: an unloaded count would read as
        // "nothing is wrong" (the same rule AdminDashboard follows).
        if (stockReady)
          AdminAttentionItem(
            label: 'Unresolved alerts',
            value: formatCount(unresolvedAlerts),
            actionLabel: 'Open monitoring',
            onAction: () => context.go(AppRoutes.adminInventory),
          ),
      ],
    );
  }
}
