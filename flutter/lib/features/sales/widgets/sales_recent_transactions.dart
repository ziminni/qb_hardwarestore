import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/sales/widgets/inventory_sales_status_badge.dart';
import 'package:flutter/material.dart';

class SalesRecentTransactions extends StatelessWidget {
  const SalesRecentTransactions({
    super.key,
    required this.sales,
    required this.onViewAll,
  });

  final List<InventorySale> sales;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final sorted = List<InventorySale>.of(sales)
      ..sort((a, b) => b.date.compareTo(a.date));
    final recent = sorted.take(5).toList();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Recent transactions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(onPressed: onViewAll, child: const Text('View all')),
              ],
            ),
          ),
          const Divider(height: 1),
          if (recent.isEmpty)
            const Padding(
              padding: EdgeInsets.all(48),
              child: Text('No sales transactions yet.'),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn(label: Text('Transaction')),
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Customer')),
                  DataColumn(label: Text('Payment')),
                  DataColumn(label: Text('Total')),
                  DataColumn(label: Text('Status')),
                ],
                rows: recent
                    .map(
                      (sale) => DataRow(
                        cells: [
                          DataCell(Text(sale.transactionNo)),
                          DataCell(
                            Text(
                              '${sale.date.month}/${sale.date.day}/${sale.date.year}',
                            ),
                          ),
                          DataCell(Text(sale.customer)),
                          DataCell(Text(sale.paymentMethod)),
                          DataCell(Text('₱${sale.total.toStringAsFixed(2)}')),
                          DataCell(
                            InventorySalesStatusBadge.sale(status: sale.status),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }
}
