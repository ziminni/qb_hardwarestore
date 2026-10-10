import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/sales_module.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_dashboard_metric_card.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_records_table.dart';
import 'package:client/features/sales/widgets/sales_status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SalesReceivablesPage extends StatelessWidget {
  const SalesReceivablesPage({super.key});
  @override
  Widget build(BuildContext context) {
    final records = context.watch<SalesModuleViewmodel>().receivables;
    final outstanding = records.fold<double>(
      0,
      (sum, item) => sum + item.balance,
    );
    final overdue = records
        .where((item) => item.status == SalesReceivableStatus.overdue)
        .fold<double>(0, (sum, item) => sum + item.balance);
    String label(SalesReceivableStatus value) => switch (value) {
      SalesReceivableStatus.dueSoon => 'Due Soon',
      SalesReceivableStatus.overdue => 'Overdue',
      _ => 'Current',
    };
    String tone(SalesReceivableStatus value) => switch (value) {
      SalesReceivableStatus.overdue => 'error',
      SalesReceivableStatus.dueSoon => 'warning',
      _ => 'success',
    };
    return SalesSkeletonLayout(
      title: 'Receivables',
      subtitle: 'Track unpaid, partial, and overdue customer balances.',
      selectedNavigationIndex: 5,
      onNavigationSelected: (index) => navigateSales(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SizedBox(
                width: 260,
                child: SalesDashboardMetricCard(
                  label: 'Outstanding',
                  value: '₱${outstanding.toStringAsFixed(2)}',
                  caption: '${records.length} open invoices',
                  icon: Icons.account_balance_wallet_outlined,
                  color: AppColors.info,
                ),
              ),
              SizedBox(
                width: 260,
                child: SalesDashboardMetricCard(
                  label: 'Overdue',
                  value: '₱${overdue.toStringAsFixed(2)}',
                  caption: 'Requires follow-up',
                  icon: Icons.warning_amber_outlined,
                  color: AppColors.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SalesRecordsTable(
            columns: const [
              'Invoice',
              'Customer',
              'Due Date',
              'Total',
              'Paid',
              'Balance',
              'Status',
              'Action',
            ],
            emptyMessage: 'No receivables available.',
            rows: records
                .map(
                  (item) => <Widget>[
                    Text(item.invoice),
                    Text(item.customer),
                    Text(
                      '${item.dueDate.month}/${item.dueDate.day}/${item.dueDate.year}',
                    ),
                    Text('₱${item.total.toStringAsFixed(2)}'),
                    Text('₱${item.paid.toStringAsFixed(2)}'),
                    Text('₱${item.balance.toStringAsFixed(2)}'),
                    SalesStatusBadge(
                      label: label(item.status),
                      tone: tone(item.status),
                    ),
                    TextButton(
                      onPressed: () {},
                      child: const Text('Record payment'),
                    ),
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
