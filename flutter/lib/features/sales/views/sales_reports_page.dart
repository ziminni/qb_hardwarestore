import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_dashboard_metric_card.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_records_table.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SalesReportsPage extends StatelessWidget {
  const SalesReportsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final sales = context.watch<InventorySalesViewmodel>().sales;
    final completed = sales
        .where((item) => item.status == InventorySaleStatus.completed)
        .toList();
    final revenue = completed.fold<double>(0, (sum, item) => sum + item.total);
    final paymentTotals = <String, double>{};
    for (final sale in completed) {
      paymentTotals[sale.paymentMethod] =
          (paymentTotals[sale.paymentMethod] ?? 0) + sale.total;
    }
    return SalesSkeletonLayout(
      title: 'Sales Reports',
      subtitle:
          'Analyze revenue, transactions, products, and payment activity.',
      selectedNavigationIndex: 6,
      onNavigationSelected: (index) => navigateSales(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Report summary',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.calendar_today_outlined),
                label: const Text('This month'),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SizedBox(
                width: 260,
                child: SalesDashboardMetricCard(
                  label: 'Net completed sales',
                  value: '₱${revenue.toStringAsFixed(2)}',
                  caption: '${completed.length} transactions',
                  icon: Icons.payments_outlined,
                  color: AppColors.success,
                ),
              ),
              SizedBox(
                width: 260,
                child: SalesDashboardMetricCard(
                  label: 'Refunded sales',
                  value:
                      '${sales.where((item) => item.status == InventorySaleStatus.refunded).length}',
                  caption: 'Transactions marked refunded',
                  icon: Icons.undo_outlined,
                  color: AppColors.warning,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SalesRecordsTable(
            columns: const [
              'Payment Method',
              'Completed Transactions',
              'Collected Amount',
              'Share',
            ],
            emptyMessage: 'No completed-sales data available.',
            rows: paymentTotals.entries.map((entry) {
              final count = completed
                  .where((sale) => sale.paymentMethod == entry.key)
                  .length;
              final share = revenue == 0 ? 0 : entry.value / revenue * 100;
              return <Widget>[
                Text(entry.key),
                Text('$count'),
                Text('₱${entry.value.toStringAsFixed(2)}'),
                Text('${share.toStringAsFixed(1)}%'),
              ];
            }).toList(),
          ),
        ],
      ),
    );
  }
}
