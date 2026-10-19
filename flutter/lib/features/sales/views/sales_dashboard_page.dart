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
      if (mounted) context.read<InventorySalesViewmodel>().load();
    });
  }

  void _selectNavigation(BuildContext context, int index) {
    navigateSales(context, index);
  }

  @override
  Widget build(BuildContext context) {
    final salesState = context.watch<InventorySalesViewmodel>();
    final completed = salesState.sales
        .where((sale) => sale.status == InventorySaleStatus.completed)
        .toList();
    // Net of refunds: RETURN rows carry negative totals (see netRevenue).
    final revenue = salesState.netRevenue;
    final average = completed.isEmpty ? 0.0 : revenue / completed.length;
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
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.calendar_today_outlined, size: 17),
                label: const Text('This month'),
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
                      caption: '${completed.length} completed transactions',
                      icon: Icons.payments_outlined,
                      color: AppColors.success,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: SalesDashboardMetricCard(
                      label: 'Transactions',
                      value: '${salesState.sales.length}',
                      caption: 'All recorded statuses',
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
