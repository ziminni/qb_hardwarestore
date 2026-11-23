import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_dashboard_alerts_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_needs_you_tile.dart';
import 'package:client/features/sales/widgets/sales_recent_transactions.dart';
import 'package:client/features/sales/widgets/sales_revenue_trend.dart';
import 'package:client/features/sales/widgets/sales_top_products.dart';
import 'package:client/shared/widgets/analytics_charts.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Store Manager's dashboard: what needs them now, then the numbers.
///
/// No page heading: the shell already says "Sales Dashboard", and two headings
/// before any figure was one too many.
class SalesDashboardPage extends StatelessWidget {
  const SalesDashboardPage({super.key, this.viewmodel});

  /// Injected by tests so the queue counts can be rendered WITHOUT a server; in
  /// production the page builds its own and loads it, like every screen-scoped
  /// viewmodel in this app (see SalesReceivablesPage).
  final SalesDashboardAlertsViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => (viewmodel ?? SalesDashboardAlertsViewmodel())..load(),
      child: const _DashboardView(),
    );
  }
}

class _DashboardView extends StatefulWidget {
  const _DashboardView();

  @override
  State<_DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<_DashboardView> {
  /// True once the transaction list has answered. Until then the returns tile
  /// says "Not loaded": an empty list is not the same fact as "zero returns".
  bool _transactionsLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadSales();
    });
  }

  Future<void> _loadSales() async {
    final sales = context.read<InventorySalesViewmodel>();
    // The top-products panel names what sold, and the sales wire carries only
    // the selling unit's id and code: the catalogue is where a name lives. One
    // shared read, once per session (the products and low-stock screens guard
    // the same way); a failure leaves the panel on the code.
    final inventory = context.read<InventoryViewmodel?>();
    if (inventory != null && !inventory.hasLoaded) inventory.load();
    // Rows and tiles fail independently: the list feeds the table, the summary
    // feeds the tiles, and neither blocks the other.
    sales.loadSummary();
    await sales.load();
    if (!mounted) return;
    if (sales.loadError == null) setState(() => _transactionsLoaded = true);
  }

  /// Re-runs both read groups. They fail independently, so the one banner's
  /// Retry repairs both rather than making the manager chase two.
  ///
  void _retryAll() {
    context.read<SalesDashboardAlertsViewmodel>().load();
    _loadSales();
  }

  void _selectNavigation(BuildContext context, int index) {
    navigateSales(context, index);
  }

  /// Returns already recorded today, counted from the rows the page has.
  /// The server posts a return final, so there is no "pending" state to count.
  int _returnsToday(List<InventoryReturn> returns) {
    final now = appClock.now();
    return returns
        .where(
          (item) =>
              item.date.year == now.year &&
              item.date.month == now.month &&
              item.date.day == now.day,
        )
        .length;
  }

  String _count(int? value) =>
      value == null ? 'Not loaded' : formatCount(value);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final salesState = context.watch<InventorySalesViewmodel>();
    final alerts = context.watch<SalesDashboardAlertsViewmodel>();
    final completed = salesState.sales
        .where((sale) => sale.status == InventorySaleStatus.completed)
        .toList();
    // Phase 5 Task 3: tiles read the server summary (correct at any scale),
    // never the client fold of a capped transaction walk. Until the summary
    // arrives the tiles fall back to the loaded rows and SAY so.
    final summary = salesState.summary;
    // "Last 30 days" is what the summary covers; "Loaded transactions" is what
    // the page's own rows cover. No third word fits a 760 px tile, and a scope
    // cut to "Last 30 days · se..." tells the reader nothing.
    final scopeCaption = summary == null
        ? 'Loaded transactions'
        : 'Last 30 days';
    // A read that has not answered established no number. Folding zero rows
    // would print a confident ₱0.00 for a failure, so the tiles say "Not
    // loaded" until either the summary or the row list has actually replied.
    final revenue =
        summary?.totalGross ??
        (_transactionsLoaded ? salesState.netRevenue : null);
    final transactionCount =
        summary?.totalTransactions ??
        (_transactionsLoaded ? completed.length : null);
    final average = revenue == null || transactionCount == null
        ? null
        : (transactionCount == 0 ? 0.0 : revenue / transactionCount);
    final returnsToday = _transactionsLoaded
        ? _returnsToday(salesState.returns)
        : null;
    // Two independent groups of reads (the overdue book, and the sales list
    // with its summary) can fail separately, but the manager needs ONE failure
    // surface and ONE Retry: two red bars saying the same thing is noise, and
    // the tiles below already say "Not loaded" wherever a read did not answer.
    // The sales reads speak first: a refused summary is what an older test pins
    // by name, and a dead transaction list is the larger loss than a dead
    // receivables count.
    final failure =
        salesState.loadError ?? salesState.summaryError ?? alerts.loadError;
    return SalesSkeletonLayout(
      title: 'Sales Dashboard',
      subtitle:
          'Monitor sales performance, transactions, and customer activity.',
      selectedNavigationIndex: 0,
      onNavigationSelected: (index) => _selectNavigation(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One banner, one retry. A failed REFRESH keeps the rows and counts
          // it already had and says why above them.
          if (failure != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: ErrorBanner(message: failure, onRetry: _retryAll),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Needs you',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              // A statement, not a control: the dashboard reads EVERY recorded
              // transaction (no date parameter exists on the load), so a "This
              // month" button that changed nothing was a lie with a border.
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.receipt_long_outlined,
                    size: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'All recorded transactions',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          MetricGrid(
            children: [
              SalesNeedsYouTile(
                key: const ValueKey('salesDashboard.needsYou.receivables'),
                label: 'Overdue receivables',
                value: _count(alerts.overdueReceivables),
                caption: 'Customers past their due date',
                icon: Icons.account_balance_wallet_outlined,
                // The receivables screen opens unfiltered: its Overdue chip is
                // that screen's own state, and preset filters would mean
                // editing a file another card owns.
                onTap: () => _selectNavigation(context, 3),
              ),
              SalesNeedsYouTile(
                key: const ValueKey('salesDashboard.needsYou.returns'),
                label: 'Returns today',
                value: _count(returnsToday),
                caption: 'Refunded or voided today',
                icon: Icons.assignment_return_outlined,
                onTap: () => _selectNavigation(context, 4),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          MetricGrid(
            children: [
              MetricTile(
                label: 'Revenue',
                value: revenue == null ? 'Not loaded' : formatPeso(revenue),
                caption: transactionCount == null
                    ? null
                    : '${formatCount(transactionCount)} completed · '
                          '$scopeCaption',
              ),
              MetricTile(
                label: 'Transactions',
                value: transactionCount == null
                    ? 'Not loaded'
                    : formatCount(transactionCount),
                caption: transactionCount == null ? null : scopeCaption,
              ),
              MetricTile(
                label: 'Average sale',
                value: average == null ? 'Not loaded' : formatPeso(average),
                caption: 'Per completed transaction',
              ),
              if (summary?.grossProfit != null)
                MetricTile(
                  label: 'Gross profit',
                  value: formatPeso(summary!.grossProfit!),
                  caption: summary.grossMarginPercent != null
                      ? '${summary.grossMarginPercent!.toStringAsFixed(1)}% margin · $scopeCaption'
                      : scopeCaption,
                ),
            ],
          ),
          if (summary?.orVatBreakdown != null) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              key: const ValueKey('sales-dashboard-vat-split'),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(AppRadii.large),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.receipt_long_outlined,
                        size: 18,
                        color: AppColors.brandGold,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          'VAT Snapshot — All Sales vs. OR-Tagged ($scopeCaption)',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () => _selectNavigation(context, 5),
                        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                        label: const Text('Full VAT & OR report'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  MetricGrid(
                    children: [
                      MetricTile(
                        label: 'Whole VAT (All Sales)',
                        value: formatPeso(summary!.orVatBreakdown!.combined.vat),
                        caption:
                            '${formatCount(summary.orVatBreakdown!.combined.transactions)} sales · '
                            '${formatPeso(summary.orVatBreakdown!.combined.grossSales)} gross',
                      ),
                      MetricTile(
                        label: 'OR-Tagged Only VAT',
                        value: formatPeso(summary.orVatBreakdown!.orBacked.vat),
                        caption:
                            '${formatCount(summary.orVatBreakdown!.orBacked.transactions)} OR-tagged · '
                            '${formatPeso(summary.orVatBreakdown!.orBacked.grossSales)} gross',
                      ),
                      MetricTile(
                        label: 'Untagged OS VAT',
                        value: formatPeso(
                          summary.orVatBreakdown!.untaggedOs.vat,
                        ),
                        caption:
                            '${formatCount(summary.orVatBreakdown!.untaggedOs.transactions)} untagged OS · '
                            '${formatPeso(summary.orVatBreakdown!.untaggedOs.grossSales)} gross',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          if (summary != null && summary.days.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            GroupedBarTrendChart(
              key: const ValueKey('sales-dashboard-profit-chart'),
              title: 'Daily Sales & Profit ($scopeCaption)',
              subtitle: summary.days.any((d) => d.cogs != null)
                  ? 'Bars compare net sales (ex-VAT) vs. landed COGS; line tracks gross profit.'
                  : 'Daily sales totals across reported dates.',
              primaryLabel: summary.days.any((d) => d.merchandiseNetExVat != null)
                  ? 'Net sales'
                  : 'Invoice total',
              secondaryLabel: 'COGS',
              lineLabel: 'Profit',
              height: 190,
              points: [
                for (final day in summary.days)
                  TrendPoint(
                    label: day.day.length >= 10 ? day.day.substring(5) : day.day,
                    primary: day.merchandiseNetExVat ?? day.gross,
                    secondary: day.cogs,
                    lineValue: day.grossProfit,
                  ),
              ],
            ),
          ],
          if (summary != null && summary.categories.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            HorizontalComparisonChart(
              key: const ValueKey('sales-dashboard-category-chart'),
              title: 'Sales & Cost by Category ($scopeCaption)',
              subtitle: 'Top categories by net merchandise sales vs. landed cost.',
              primaryLabel: 'Net sales',
              secondaryLabel: 'COGS',
              items: [
                for (final cat in summary.categories.take(6))
                  ComparisonBarItem(
                    label: cat.categoryName,
                    primaryValue: cat.netMerchandise,
                    primaryText: formatPeso(cat.netMerchandise),
                    secondaryValue: cat.cogs,
                    secondaryText: cat.cogs != null
                        ? 'COGS ${formatPeso(cat.cogs!)}'
                        : null,
                  ),
              ],
            ),
          ],
          // The panels below read the transaction list. Until it answers there
          // is nothing honest to draw there: a "No completed sales yet" panel
          // under a failure banner would claim a fact the failed read never
          // established, so the banner is the whole story.
          if (_transactionsLoaded) ...[
            const SizedBox(height: AppSpacing.lg),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 820) {
                  return Column(
                    children: [
                      SalesRevenueTrend(sales: salesState.sales),
                      const SizedBox(height: AppSpacing.lg),
                      SalesTopProducts(sales: salesState.sales),
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: SalesRevenueTrend(sales: salesState.sales),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      flex: 2,
                      child: SalesTopProducts(sales: salesState.sales),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.lg),
            SalesRecentTransactions(
              sales: salesState.sales,
              isLoading: salesState.isLoading && salesState.sales.isEmpty,
              onViewAll: () => _selectNavigation(context, 1),
            ),
          ],
        ],
      ),
    );
  }
}
