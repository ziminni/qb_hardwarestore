import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_dashboard_metric_card.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:client/features/sales/widgets/sales_recent_transactions.dart';
import 'package:client/features/sales/widgets/sales_revenue_trend.dart';
import 'package:client/features/sales/widgets/sales_top_products.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SalesDashboardPage extends StatefulWidget {
  const SalesDashboardPage({super.key});

  @override
  State<SalesDashboardPage> createState() => _SalesDashboardPageState();
}

class _SalesDashboardPageState extends State<SalesDashboardPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final sales = context.read<InventorySalesViewmodel>();
      // Rows and tiles fail independently: the list feeds tables, the
      // summary feeds tiles, and neither blocks the other.
      sales.load();
      sales.loadSummary();
    });
  }

  void _selectNavigation(BuildContext context, int index) {
    navigateSales(context, index);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final salesState = context.watch<InventorySalesViewmodel>();
    final completed = salesState.sales
        .where((sale) => sale.status == InventorySaleStatus.completed)
        .toList();
    // Phase 5 Task 3: tiles read the server summary (correct at any scale),
    // never the client fold of a capped transaction walk. Until the summary
    // arrives the tiles fall back to the loaded rows and SAY so.
    final summary = salesState.summary;
    final revenue = summary?.totalGross ?? salesState.netRevenue;
    final transactionCount = summary?.totalTransactions ?? completed.length;
    final average = transactionCount == 0 ? 0.0 : revenue / transactionCount;
    final scopeCaption = summary == null
        ? 'Loaded transactions'
        : 'Last 30 days · server';
    final pendingReturns = salesState.returns
        .where(
          (item) =>
              item.status == InventoryReturnStatus.pending ||
              item.status == InventoryReturnStatus.approved,
        )
        .length;
    return SalesSkeletonLayout(
      title: 'Sales Dashboard',
      subtitle:
          'Monitor sales performance, transactions, and customer activity.',
      selectedNavigationIndex: 0,
      onNavigationSelected: (index) => _selectNavigation(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (salesState.loadError != null)
            LiveLoadErrorBanner(
              message: salesState.loadError!,
              onRetry: salesState.load,
            ),
          // Tiles and rows fail independently: a dead summary keeps honest
          // row-based tiles out of the picture only when it must. While the
          // summary is missing the tiles say which transactions they fold.
          if (salesState.summaryError != null)
            LiveLoadErrorBanner(
              message: salesState.summaryError!,
              onRetry: salesState.loadSummary,
            ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sales overview',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text('Live sales activity'),
                  ],
                ),
              ),
              // A statement, not a control: the dashboard reads EVERY
              // recorded transaction (no date parameter exists on the load),
              // so a "This month" button that changed nothing was a lie with a
              // border. It now says what is actually on screen.
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
          const SizedBox(height: AppSpacing.xl),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = AppSpacing.md;
              final columns = constraints.maxWidth >= 980
                  ? 4
                  : constraints.maxWidth >= 520
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  SizedBox(
                    width: width,
                    child: SalesDashboardMetricCard(
                      label: 'Completed revenue',
                      value: '₱${revenue.toStringAsFixed(2)}',
                      caption: summary == null
                          ? '${completed.length} completed · $scopeCaption'
                          : '$transactionCount completed · $scopeCaption',
                      icon: Icons.payments_outlined,
                      color: AppColors.success,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: SalesDashboardMetricCard(
                      label: 'Transactions',
                      value: '$transactionCount',
                      caption: scopeCaption,
                      icon: Icons.receipt_long_outlined,
                      color: AppColors.info,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: SalesDashboardMetricCard(
                      label: 'Average sale',
                      value: '₱${average.toStringAsFixed(2)}',
                      caption: 'Per completed transaction',
                      icon: Icons.trending_up,
                      color: AppColors.brandGold,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: SalesDashboardMetricCard(
                      label: 'Open returns',
                      value: '$pendingReturns',
                      caption: 'Pending or approved',
                      icon: Icons.assignment_return_outlined,
                      color: AppColors.warning,
                    ),
                  ),
                ],
              );
            },
          ),
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
            onViewAll: () => _selectNavigation(context, 1),
          ),
        ],
      ),
    );
  }
}
