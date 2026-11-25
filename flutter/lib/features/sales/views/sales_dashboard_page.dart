import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/time/app_clock.dart';
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
import 'package:client/shared/widgets/stitch_ui.dart';
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
    final scopeCaption = summary == null
        ? 'Loaded transactions'
        : activePreset.label;
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
    final kpisUnloaded =
        revenue == null && transactionCount == null && average == null;
    final failure =
        salesState.loadError ?? salesState.summaryError ?? alerts.loadError;

    final hasTrendDays = summary != null && summary.days.isNotEmpty;
    final hasScopedSales = _transactionsLoaded && scopedCompleted.isNotEmpty;

    return SalesSkeletonLayout(
      title: 'Sales Dashboard',
      subtitle:
          'Monitor sales performance, transactions, and customer activity.',
      selectedNavigationIndex: 0,
      onNavigationSelected: (index) => _selectNavigation(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (failure != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: ErrorBanner(message: failure, onRetry: _retryAll),
            ),
          // Top Control Bar
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
                  color: StitchColors.ink,
                ),
              ),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StitchSegmentedBar<_DashboardRangePreset>(
                    selected: _preset,
                    onSelected: _selectPreset,
                    items: [
                      for (final preset in _DashboardRangePreset.values)
                        (
                          value: preset,
                          label: _presetRange(preset).chipLabel,
                          key: ValueKey('sales-dashboard-preset-${preset.name}'),
                        ),
                    ],
                  ),
                  FilledButton.icon(
                    key: const ValueKey('sales-dashboard-audit-vat'),
                    onPressed: () =>
                        _selectNavigation(context, _row('reports')),
                    style: FilledButton.styleFrom(
                      backgroundColor: StitchColors.primaryDeep,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(Icons.account_balance_outlined, size: 16),
                    label: const Text('Audit VAT Ledger'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('sales-dashboard-refresh'),
                    onPressed: _retryAll,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: StitchColors.ink,
                      side: const BorderSide(color: StitchColors.cardBorder),
                      backgroundColor: StitchColors.card,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          // Actionable "Needs you" tiles
          MetricGrid(
            children: [
              SalesNeedsYouTile(
                key: const ValueKey('salesDashboard.needsYou.receivables'),
                label: 'Overdue receivables',
                value: _count(alerts.overdueReceivables),
                caption: 'Customers past their due date',
                icon: Icons.account_balance_wallet_outlined,
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
          // 4-Column Stitch Hero KPI Strip
          if (kpisUnloaded)
            const MetricGrid(
              minTileWidth: 230,
              children: [
                MetricTile(label: 'Revenue', value: 'Not loaded'),
                MetricTile(label: 'Transactions', value: 'Not loaded'),
                MetricTile(
                  label: 'Average sale',
                  value: 'Not loaded',
                  caption: 'Per completed transaction',
                ),
              ],
            )
          else
            MetricGrid(
              minTileWidth: 230,
              children: [
                StitchKpiCard(
                  label: 'Revenue',
                  value: revenue == null ? 'Not loaded' : formatPeso(revenue),
                  icon: Icons.payments_outlined,
                  tone: StitchTone.primary,
                  subtitle: transactionCount == null
                      ? null
                      : '${formatCount(transactionCount)} completed · $scopeCaption',
                  pillLabel: scopeCaption,
                  pillTone: StitchTone.primary,
                ),
                StitchKpiCard(
                  label: 'Transactions',
                  value: transactionCount == null
                      ? 'Not loaded'
                      : formatCount(transactionCount),
                  icon: Icons.receipt_long_outlined,
                  tone: StitchTone.primary,
                  subtitle: 'Completed sales slips',
                  pillLabel: transactionCount == null ? null : scopeCaption,
                  pillTone: StitchTone.primary,
                ),
                StitchKpiCard(
                  label: 'Average sale',
                  value: average == null ? 'Not loaded' : formatPeso(average),
                  icon: Icons.analytics_outlined,
                  tone: StitchTone.primary,
                  subtitle: 'Per completed transaction',
                  pillLabel: 'Basket average',
                  pillTone: StitchTone.neutral,
                ),
                if (summary?.grossProfit != null)
                  StitchKpiCard(
                    label: 'Gross profit',
                    value: formatPeso(summary!.grossProfit!),
                    icon: Icons.trending_up,
                    tone: summary.grossProfit! >= 0
                        ? StitchTone.success
                        : StitchTone.danger,
                    valueColor: summary.grossProfit! >= 0
                        ? StitchColors.successInk
                        : StitchColors.danger,
                    subtitle: scopeCaption,
                    pillLabel: summary.grossMarginPercent != null
                        ? '${summary.grossMarginPercent!.toStringAsFixed(1)}% margin'
                        : scopeCaption,
                    pillTone: summary.grossProfit! >= 0
                        ? StitchTone.success
                        : StitchTone.danger,
                  )
                else if (summary?.orVatBreakdown != null)
                  StitchKpiCard(
                    label: 'OR-Tagged VAT',
                    value: formatPeso(summary!.orVatBreakdown!.orBacked.vat),
                    icon: Icons.verified_outlined,
                    tone: StitchTone.primary,
                    subtitle:
                        '12% Output on ${formatPeso(summary.orVatBreakdown!.orBacked.vatableSales)} base',
                    pillLabel:
                        '${formatCount(summary.orVatBreakdown!.orBacked.transactions)} OR Invoices',
                    pillTone: StitchTone.primary,
                  ),
              ],
            ),
          // 3-Column Dual-Stream Tax Segregation Card
          if (summary?.orVatBreakdown != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _DualStreamTaxCard(
              breakdown: summary!.orVatBreakdown!,
              scopeCaption: scopeCaption,
              onOpenReport: () => _selectNavigation(context, _row('reports')),
            ),
          ],
          // 2-Column Chart Hero
          if (_preset == _DashboardRangePreset.today && hasScopedSales) ...[
            const SizedBox(height: AppSpacing.lg),
            _HourlyAndTenderRow(
              scopedCompleted: scopedCompleted,
              scopeCaption: scopeCaption,
            ),
          ] else if (_preset != _DashboardRangePreset.today &&
              (hasTrendDays || hasScopedSales)) ...[
            const SizedBox(height: AppSpacing.lg),
            _TrendAndTenderRow(
              summary: hasTrendDays ? summary : null,
              scopedCompleted: hasScopedSales ? scopedCompleted : const [],
              scopeCaption: scopeCaption,
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
          if (inventoryState != null && inventoryState.products.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            _StockSnapshotCard(
              inventory: inventoryState,
              onOpenInventory: () =>
                  _selectNavigation(context, _row('sales.inventory')),
            ),
          ],
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
    final orFlex = (orPct * 10).round();
    final osFlex = (osPct * 10).round();

    final orBox = StitchAccentBox(
      accentColor: StitchColors.primaryDeep,
      backgroundColor: StitchColors.primarySoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.verified_outlined,
                    size: 15,
                    color: StitchColors.primaryDeep,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'OR-Tagged Official Receipt (OR)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: StitchColors.primaryDeep,
                    ),
                  ),
                ],
              ),
              StitchPill(
                label: '${formatCount(breakdown.orBacked.transactions)} OR Invoices',
                tone: StitchTone.primary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'GROSS OR SALES',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: StitchColors.inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatPeso(breakdown.orBacked.grossSales),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: StitchColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: StitchColors.divider),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TaxSubMetric(
                  label: 'VATABLE BASE',
                  value: formatPeso(breakdown.orBacked.vatableSales),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TaxSubMetric(
                  label: '12% OUTPUT VAT',
                  value: formatPeso(breakdown.orBacked.vat),
                  valueColor: StitchColors.primaryDeep,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final osBox = StitchAccentBox(
      accentColor: StitchColors.primary,
      backgroundColor: StitchColors.surfaceCanvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 15,
                    color: StitchColors.primary,
                  ),
                  SizedBox(width: 6),
                  Text(
                    'Untagged Order Slips (OS)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: StitchColors.primary,
                    ),
                  ),
                ],
              ),
              StitchPill(
                label: '${formatCount(breakdown.untaggedOs.transactions)} Order Slips',
                tone: StitchTone.neutral,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'INTERNAL OS SALES',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: StitchColors.inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatPeso(breakdown.untaggedOs.grossSales),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: StitchColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: StitchColors.divider),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TaxSubMetric(
                  label: 'VATABLE BASE',
                  value: formatPeso(breakdown.untaggedOs.vatableSales),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TaxSubMetric(
                  label: 'ESTIMATED VAT',
                  value: formatPeso(breakdown.untaggedOs.vat),
                  valueColor: StitchColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final consolidatedBox = StitchAccentBox(
      accentColor: StitchColors.success,
      backgroundColor: const Color(0xFFF0FDF4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Consolidated Turnover (OR + OS)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: StitchColors.successInk,
                ),
              ),
              StitchPill(label: 'Reconciled', tone: StitchTone.success),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'TOTAL GROSS (OR + OS)',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: StitchColors.inkMuted,
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatPeso(breakdown.combined.grossSales),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: StitchColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Total VAT ${formatPeso(breakdown.combined.vat)} · ${formatCount(breakdown.combined.transactions)} slips',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: StitchColors.inkMuted,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'OR ${orPct.toStringAsFixed(0)}%',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: StitchColors.primaryDeep,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  'OS ${osPct.toStringAsFixed(0)}%',
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  if (orFlex > 0)
                    Expanded(
                      flex: orFlex,
                      child: Container(color: StitchColors.primaryDeep),
                    ),
                  if (osFlex > 0)
                    Expanded(
                      flex: osFlex,
                      child: Container(color: const Color(0xFF60A5FA)),
                    ),
                  if (orFlex == 0 && osFlex == 0)
                    Expanded(
                      child: Container(color: StitchColors.cardBorder),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return StitchSectionCard(
      key: const ValueKey('sales-dashboard-vat-split'),
      icon: Icons.account_balance_outlined,
      overline: 'DUAL-STREAM TAX SEGREGATION',
      title: 'Official Receipt (OR) vs. Untagged Order Slips',
      subtitle:
          'Contrasting 12% Output VAT on OR-tagged sales against untagged internal order slips ($scopeCaption).',
      trailing: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StitchPill(
            label:
                '${orPct.toStringAsFixed(0)}% OR / ${osPct.toStringAsFixed(0)}% OS',
            tone: StitchTone.primary,
          ),
          FilledButton.icon(
            onPressed: onOpenReport,
            style: FilledButton.styleFrom(
              backgroundColor: StitchColors.primaryDeep,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: const Text('Full VAT & OR report'),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 860) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                orBox,
                const SizedBox(height: AppSpacing.sm),
                osBox,
                const SizedBox(height: AppSpacing.sm),
                consolidatedBox,
              ],
            );
          }
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: orBox),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: osBox),
                const SizedBox(width: AppSpacing.sm),
                Expanded(child: consolidatedBox),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TaxSubMetric extends StatelessWidget {
  const _TaxSubMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: StitchColors.inkMuted,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: valueColor ?? StitchColors.ink,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
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

class _TrendAndTenderRow extends StatelessWidget {
  const _TrendAndTenderRow({
    required this.summary,
    required this.scopedCompleted,
    required this.scopeCaption,
  });

  final SalesSummary? summary;
  final List<InventorySale> scopedCompleted;
  final String scopeCaption;

  @override
  Widget build(BuildContext context) {
    final trendChart = summary == null
        ? null
        : GroupedBarTrendChart(
            key: const ValueKey('sales-dashboard-profit-chart'),
            title: 'Daily Sales & Profit ($scopeCaption)',
            subtitle: summary!.days.any((d) => d.cogs != null)
                ? 'Bars compare net sales (ex-VAT) vs. landed COGS; line tracks gross profit.'
                : 'Daily sales totals across reported dates.',
            primaryLabel:
                summary!.days.any((d) => d.merchandiseNetExVat != null)
                ? 'Net sales'
                : 'Invoice total',
            secondaryLabel: 'COGS',
            lineLabel: 'Profit',
            height: 190,
            points: [
              for (final day in summary!.days)
                TrendPoint(
                  label: day.day.length >= 10
                      ? day.day.substring(5)
                      : day.day,
                  primary: day.merchandiseNetExVat ?? day.gross,
                  secondary: day.cogs,
                  lineValue: day.grossProfit,
                ),
            ],
          );
    final tenderChart = scopedCompleted.isEmpty
        ? null
        : _buildTenderDonut(scopedCompleted, scopeCaption);

    if (trendChart != null && tenderChart == null) return trendChart;
    if (trendChart == null && tenderChart != null) return tenderChart;
    if (trendChart == null && tenderChart == null) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 860) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              trendChart!,
              const SizedBox(height: AppSpacing.md),
              tenderChart!,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: trendChart!),
            const SizedBox(width: AppSpacing.md),
            Expanded(flex: 2, child: tenderChart!),
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
    return StitchSectionCard(
      key: const ValueKey('sales-dashboard-stock-snapshot'),
      icon: Icons.inventory_2_outlined,
      overline: 'STORE & BODEGA INVENTORY',
      title: 'Store Stock & Restock Snapshot',
      subtitle: 'Live catalog health and FIFO landed stock valuation.',
      trailing: FilledButton.tonalIcon(
        onPressed: onOpenInventory,
        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
        label: const Text('Inventory & Sales'),
      ),
      child: MetricGrid(
        minTileWidth: 210,
        children: [
          StitchKpiCard(
            label: 'Active Products',
            value: formatCount(inventory.products.length),
            icon: Icons.category_outlined,
            tone: StitchTone.primary,
            subtitle: '${formatCount(inStock)} variants healthy',
            pillLabel: 'Catalog',
            pillTone: StitchTone.primary,
          ),
          StitchKpiCard(
            label: 'FIFO Stock Value',
            value: formatPeso(stockValue),
            icon: Icons.account_balance_wallet_outlined,
            tone: StitchTone.success,
            subtitle: 'On-hand landed cost',
            pillLabel: 'FIFO valuation',
            pillTone: StitchTone.success,
          ),
          StitchKpiCard(
            label: 'Low Stock',
            value: formatCount(lowStock),
            icon: Icons.warning_amber_rounded,
            tone: lowStock > 0 ? StitchTone.warning : StitchTone.neutral,
            valueColor:
                lowStock > 0 ? StitchColors.warningInk : StitchColors.ink,
            subtitle: 'Below reorder point',
            pillLabel: lowStock > 0 ? 'Reorder soon' : 'All healthy',
            pillTone: lowStock > 0 ? StitchTone.warning : StitchTone.success,
          ),
          StitchKpiCard(
            label: 'Out of Stock',
            value: formatCount(outOfStock),
            icon: Icons.remove_shopping_cart_outlined,
            tone: outOfStock > 0 ? StitchTone.danger : StitchTone.neutral,
            valueColor: outOfStock > 0 ? StitchColors.danger : StitchColors.ink,
            subtitle: 'Needs immediate restock',
            pillLabel: outOfStock > 0 ? 'Action needed' : 'Zero stockouts',
            pillTone: outOfStock > 0 ? StitchTone.danger : StitchTone.success,
          ),
        ],
      ),
    );
  }
}
