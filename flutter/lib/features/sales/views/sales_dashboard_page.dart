import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/constants/app_areas.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/reports.dart';
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

enum _DashboardRangePreset { today, thisWeek, thisMonth, last30Days }

class _DashboardViewState extends State<_DashboardView> {
  /// True once the transaction list has answered. Until then the returns tile
  /// says "Not loaded": an empty list is not the same fact as "zero returns".
  bool _transactionsLoaded = false;
  _DashboardRangePreset _preset = _DashboardRangePreset.last30Days;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadSales();
    });
  }

  String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  ({String? from, String? to, DateTime startDate, String label, String chipLabel})
  _presetRange(_DashboardRangePreset preset) {
    final now = appClock.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (preset) {
      _DashboardRangePreset.today => (
        from: _isoDate(today),
        to: _isoDate(today),
        startDate: today,
        label: 'Today',
        chipLabel: 'Daily (Today)',
      ),
      _DashboardRangePreset.thisWeek => (
        from: _isoDate(today.subtract(const Duration(days: 6))),
        to: _isoDate(today),
        startDate: today.subtract(const Duration(days: 6)),
        label: 'Weekly (7 Days)',
        chipLabel: 'Weekly (7 Days)',
      ),
      _DashboardRangePreset.thisMonth => (
        from: _isoDate(DateTime(today.year, today.month, 1)),
        to: _isoDate(today),
        startDate: DateTime(today.year, today.month, 1),
        label: 'Monthly (MTD)',
        chipLabel: 'Monthly (MTD)',
      ),
      _DashboardRangePreset.last30Days => (
        from: null,
        to: null,
        startDate: today.subtract(const Duration(days: 30)),
        label: 'Last 30 days',
        chipLabel: 'Last 30 days',
      ),
    };
  }

  Future<void> _selectPreset(_DashboardRangePreset preset) async {
    if (_preset == preset) return;
    setState(() => _preset = preset);
    final range = _presetRange(preset);
    await context.read<InventorySalesViewmodel>().loadSummary(
      from: range.from,
      to: range.to,
    );
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
    final range = _presetRange(_preset);
    sales.loadSummary(from: range.from, to: range.to);
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

  /// The sidebar index of a sales row, looked up instead of written down: a row
  /// hidden or restored above this page moves it, and a stale number sends the
  /// manager to the wrong screen.
  static int _row(String id) => AppDestinations.indexOf(id, AppAreas.sales);

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
    final inventoryState = context.watch<InventoryViewmodel?>();
    final activePreset = _presetRange(_preset);
    final completed = salesState.sales
        .where((sale) => sale.status == InventorySaleStatus.completed)
        .toList();
    final scopedCompleted = completed
        .where((sale) => !sale.date.isBefore(activePreset.startDate))
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
        : _presetRange(_preset).label;
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
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Text(
                'Needs you',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final preset in _DashboardRangePreset.values)
                    ChoiceChip(
                      key: ValueKey('sales-dashboard-preset-${preset.name}'),
                      label: Text(_presetRange(preset).chipLabel),
                      selected: _preset == preset,
                      onSelected: (_) => _selectPreset(preset),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('sales-dashboard-audit-vat'),
                    onPressed: () =>
                        _selectNavigation(context, _row('reports')),
                    icon: const Icon(Icons.account_balance_outlined, size: 16),
                    label: const Text('Audit VAT Ledger'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('sales-dashboard-refresh'),
                    onPressed: _retryAll,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Refresh'),
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
                onTap: () =>
                    _selectNavigation(context, _row('sales.receivables')),
              ),
              SalesNeedsYouTile(
                key: const ValueKey('salesDashboard.needsYou.returns'),
                label: 'Returns today',
                value: _count(returnsToday),
                caption: 'Refunded or voided today',
                icon: Icons.assignment_return_outlined,
                onTap: () => _selectNavigation(context, _row('sales.returns')),
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
            _DualStreamTaxCard(
              breakdown: summary!.orVatBreakdown!,
              scopeCaption: scopeCaption,
              onOpenReport: () => _selectNavigation(context, _row('reports')),
            ),
          ],
          if (_preset == _DashboardRangePreset.today &&
              _transactionsLoaded &&
              scopedCompleted.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _HourlyAndTenderRow(
              scopedCompleted: scopedCompleted,
              scopeCaption: scopeCaption,
            ),
          ] else if (summary != null && summary.days.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            GroupedBarTrendChart(
              key: const ValueKey('sales-dashboard-profit-chart'),
              title: 'Daily Sales & Profit ($scopeCaption)',
              subtitle: summary.days.any((d) => d.cogs != null)
                  ? 'Bars compare net sales (ex-VAT) vs. landed COGS; line tracks gross profit.'
                  : 'Daily sales totals across reported dates.',
              primaryLabel:
                  summary.days.any((d) => d.merchandiseNetExVat != null)
                  ? 'Net sales'
                  : 'Invoice total',
              secondaryLabel: 'COGS',
              lineLabel: 'Profit',
              height: 190,
              points: [
                for (final day in summary.days)
                  TrendPoint(
                    label: day.day.length >= 10
                        ? day.day.substring(5)
                        : day.day,
                    primary: day.merchandiseNetExVat ?? day.gross,
                    secondary: day.cogs,
                    lineValue: day.grossProfit,
                  ),
              ],
            ),
          ],
          if (summary != null && summary.merchandiseGross != null) ...[
            const SizedBox(height: AppSpacing.lg),
            ProfitBreakdownCard(sales: summary),
          ],
          if (summary != null && summary.categories.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            HorizontalComparisonChart(
              key: const ValueKey('sales-dashboard-category-chart'),
              title: 'Sales & Cost by Category ($scopeCaption)',
              subtitle:
                  'Top categories by net merchandise sales vs. landed cost.',
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
          if (_transactionsLoaded &&
              scopedCompleted.isNotEmpty &&
              _preset != _DashboardRangePreset.today) ...[
            const SizedBox(height: AppSpacing.lg),
            _TenderAndOrSplitRow(
              completed: scopedCompleted,
              scopeCaption: scopeCaption,
              orVatBreakdown: summary?.orVatBreakdown,
            ),
          ],
          if (inventoryState != null && inventoryState.products.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _StockSnapshotCard(
              inventory: inventoryState,
              onOpenInventory: () =>
                  _selectNavigation(context, _row('sales.inventory')),
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
              onViewAll: () =>
                  _selectNavigation(context, _row('sales.transactions')),
            ),
          ],
        ],
      ),
    );
  }
}

class _DualStreamTaxCard extends StatelessWidget {
  const _DualStreamTaxCard({
    required this.breakdown,
    required this.scopeCaption,
    required this.onOpenReport,
  });

  final OrVatSplit breakdown;
  final String scopeCaption;
  final VoidCallback onOpenReport;

  @override
  Widget build(BuildContext context) {
    final totalGross = breakdown.combined.grossSales;
    final orPct = totalGross > 0
        ? (breakdown.orBacked.grossSales / totalGross * 100)
        : 0.0;
    final osPct = totalGross > 0
        ? (breakdown.untaggedOs.grossSales / totalGross * 100)
        : 0.0;

    return Container(
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
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.receipt_long_outlined,
                    size: 18,
                    color: AppColors.brandGold,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Official Receipt (OR) vs. Untagged Order Slips ($scopeCaption)',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: onOpenReport,
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Full VAT & OR report'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          MetricGrid(
            children: [
              MetricTile(
                label: 'OR-Tagged Only (Official Receipt)',
                value: formatPeso(breakdown.orBacked.vat),
                caption:
                    '${formatCount(breakdown.orBacked.transactions)} OR-tagged (${orPct.toStringAsFixed(0)}%) · '
                    '${formatPeso(breakdown.orBacked.grossSales)} gross · '
                    'Base ${formatPeso(breakdown.orBacked.vatableSales)}',
              ),
              MetricTile(
                label: 'Untagged Order Slips (OS)',
                value: formatPeso(breakdown.untaggedOs.vat),
                caption:
                    '${formatCount(breakdown.untaggedOs.transactions)} untagged OS (${osPct.toStringAsFixed(0)}%) · '
                    '${formatPeso(breakdown.untaggedOs.grossSales)} gross · '
                    'Base ${formatPeso(breakdown.untaggedOs.vatableSales)}',
              ),
              MetricTile(
                label: 'Consolidated Turnover (OR + OS)',
                value: formatPeso(breakdown.combined.grossSales),
                caption:
                    '${formatCount(breakdown.combined.transactions)} total sales · '
                    'Total VAT ${formatPeso(breakdown.combined.vat)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HourlyAndTenderRow extends StatelessWidget {
  const _HourlyAndTenderRow({
    required this.scopedCompleted,
    required this.scopeCaption,
  });

  final List<InventorySale> scopedCompleted;
  final String scopeCaption;

  @override
  Widget build(BuildContext context) {
    final byHour = <int, double>{};
    for (final sale in scopedCompleted) {
      final h = sale.date.hour;
      byHour[h] = (byHour[h] ?? 0) + sale.total;
    }
    final hourlyChart = TimeOfDayChart(
      key: const ValueKey('sales-dashboard-hourly-chart'),
      title: 'Hourly Revenue Stream ($scopeCaption)',
      subtitle: 'Completed invoice revenue plotted by hour of day.',
      byHour: byHour,
      valueLabel: 'Hourly sales',
      height: 190,
    );
    final tenderChart = _buildTenderDonut(scopedCompleted, scopeCaption);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              hourlyChart,
              const SizedBox(height: AppSpacing.md),
              tenderChart,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: hourlyChart),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 2, child: tenderChart),
          ],
        );
      },
    );
  }
}

DonutChart _buildTenderDonut(
  List<InventorySale> completed,
  String scopeCaption,
) {
  final totalsByMethod = <String, double>{};
  for (final sale in completed) {
    final key = sale.paymentMethod.trim().isEmpty
        ? 'Other'
        : sale.paymentMethod.trim();
    totalsByMethod[key] = (totalsByMethod[key] ?? 0) + sale.total;
  }
  final sorted = totalsByMethod.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final total = sorted.fold<double>(0, (sum, e) => sum + e.value);

  return DonutChart(
    key: const ValueKey('sales-dashboard-tender-donut'),
    title: 'Payment / Tender Mix ($scopeCaption)',
    subtitle: 'Completed sales share across payment methods.',
    centerLabel: 'Intake',
    centerValue: formatPeso(total),
    slices: [
      for (final entry in sorted.take(6))
        ShareSlice(
          label: entry.key,
          value: entry.value,
          amountText: formatPeso(entry.value),
        ),
    ],
  );
}

class _StockSnapshotCard extends StatelessWidget {
  const _StockSnapshotCard({
    required this.inventory,
    required this.onOpenInventory,
  });

  final InventoryViewmodel inventory;
  final VoidCallback onOpenInventory;

  @override
  Widget build(BuildContext context) {
    var inStock = 0;
    var lowStock = 0;
    var outOfStock = 0;
    for (final product in inventory.products) {
      for (final variant in product.variants) {
        final status = inventory.statusForVariant(variant.id);
        if (status == InventoryStockStatus.inStock) inStock++;
        if (status == InventoryStockStatus.lowStock) lowStock++;
        if (status == InventoryStockStatus.outOfStock) outOfStock++;
      }
    }
    final stockValue = inventory.batches.fold<double>(
      0,
      (sum, batch) => sum + batch.currentQty * batch.unitCostLanded,
    );
    return Container(
      key: const ValueKey('sales-dashboard-stock-snapshot'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadii.large),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  SizedBox(width: AppSpacing.xs),
                  Text(
                    'Store Stock & Restock Snapshot',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: onOpenInventory,
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Inventory & Sales'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          MetricGrid(
            children: [
              MetricTile(
                label: 'Active Products',
                value: formatCount(inventory.products.length),
                caption: '${formatCount(inStock)} variants healthy',
              ),
              MetricTile(
                label: 'FIFO Stock Value',
                value: formatPeso(stockValue),
                caption: 'On-hand landed cost',
              ),
              MetricTile(
                label: 'Low Stock',
                value: formatCount(lowStock),
                caption: 'Below reorder point',
              ),
              MetricTile(
                label: 'Out of Stock',
                value: formatCount(outOfStock),
                caption: 'Needs immediate restock',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TenderAndOrSplitRow extends StatelessWidget {
  const _TenderAndOrSplitRow({
    required this.completed,
    required this.scopeCaption,
    required this.orVatBreakdown,
  });

  final List<InventorySale> completed;
  final String scopeCaption;
  final OrVatSplit? orVatBreakdown;

  @override
  Widget build(BuildContext context) {
    final tenderChart = _buildTenderDonut(completed, scopeCaption);

    final orChart = orVatBreakdown == null
        ? null
        : ShareSplitChart(
            key: const ValueKey('sales-dashboard-or-split'),
            title: 'OR-Tagged vs. Untagged Order Slips',
            subtitle: 'Gross sales split by official receipt attachment.',
            slices: [
              ShareSlice(
                label: 'OR-Tagged Only (Official Receipt)',
                value: orVatBreakdown!.orBacked.grossSales,
                amountText: formatPeso(orVatBreakdown!.orBacked.grossSales),
              ),
              ShareSlice(
                label: 'Untagged Order Slips',
                value: orVatBreakdown!.untaggedOs.grossSales,
                amountText: formatPeso(orVatBreakdown!.untaggedOs.grossSales),
              ),
            ],
          );

    if (orChart == null) return tenderChart;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 820) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tenderChart,
              const SizedBox(height: AppSpacing.md),
              orChart,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: tenderChart),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 2, child: orChart),
          ],
        );
      },
    );
  }
}
