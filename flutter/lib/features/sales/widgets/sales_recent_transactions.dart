import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/sales/widgets/inventory_sales_status_badge.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:flutter/material.dart';

/// The dashboard's short list of the newest sales: five rows, then "View all".
///
/// On [DataPanel] rather than a raw [DataTable] so the rows become cards under
/// 720 px of panel width instead of scrolling sideways on the manager's window.
class SalesRecentTransactions extends StatelessWidget {
  const SalesRecentTransactions({
    super.key,
    required this.sales,
    required this.onViewAll,
    this.isLoading = false,
  });

  final List<InventorySale> sales;
  final VoidCallback onViewAll;

  /// True only on a first load with nothing to show yet: rows that already
  /// arrived stay on screen while the list refreshes.
  final bool isLoading;

  /// How many rows the dashboard shows; the rest are one tap away.
  static const int rowsShown = 5;

  @override
  Widget build(BuildContext context) {
    final sorted = List<InventorySale>.of(sales)
      ..sort((a, b) => b.date.compareTo(a.date));
    final recent = sorted.take(rowsShown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Recent transactions',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(onPressed: onViewAll, child: const Text('View all')),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        DataPanel<InventorySale>(
          rows: recent,
          isLoading: isLoading,
          emptyMessage: 'No sales transactions yet.',
          rowKey: (sale) => ValueKey('recent.${sale.transactionNo}'),
          columns: [
            DataPanelColumn(
              label: 'Transaction',
              flex: 2,
              cell: (sale) => Text(
                sale.transactionNo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DataPanelColumn(
              label: 'Date',
              cell: (sale) => Text(
                formatDate(sale.date),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DataPanelColumn(
              label: 'Customer',
              flex: 2,
              cell: (sale) => Text(
                sale.customer,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DataPanelColumn(
              label: 'Total',
              numeric: true,
              cell: (sale) => Text(formatPeso(sale.total)),
            ),
            DataPanelColumn(
              label: 'Status',
              cell: (sale) =>
                  InventorySalesStatusBadge.sale(status: sale.status),
            ),
          ],
        ),
      ],
    );
  }
}
