import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/sales/widgets/sales_transactions_content.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:client/shared/widgets/stitch_ui.dart';
import 'package:flutter/material.dart';

/// The dashboard's live stream of the newest sales: five rows, clickable to
/// open the full transaction detail sheet with every item bought, plus "View all".
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

  bool _isTagged(InventorySale sale) =>
      sale.invoiceNo != null && sale.invoiceNo!.trim().isNotEmpty;

  String _itemsSummary(InventorySale sale) {
    if (sale.lines.isEmpty) return 'No items';
    final parts = [
      for (final line in sale.lines.take(2))
        '${formatQuantity(line.quantity)}x ${line.productName}',
    ];
    final extra = sale.lines.length - 2;
    return extra > 0 ? '${parts.join(', ')} +$extra more' : parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final sorted = List<InventorySale>.of(sales)
      ..sort((a, b) => b.date.compareTo(a.date));
    final recent = sorted.take(rowsShown).toList();
    return StitchSectionCard(
      overline: 'LIVE STORE TRANSACTION STREAM',
      title: 'Recent transactions',
      subtitle: 'Tap any row to inspect full details and every item bought.',
      icon: Icons.receipt_long_outlined,
      trailing: TextButton.icon(
        onPressed: onViewAll,
        icon: const Icon(Icons.arrow_forward_rounded, size: 16),
        label: const Text('View all'),
      ),
      child: DataPanel<InventorySale>(
        rows: recent,
        isLoading: isLoading,
        emptyMessage: 'No sales transactions yet.',
        rowKey: (sale) => ValueKey('recent.${sale.transactionNo}'),
        onRowTap: (sale) =>
            showInventorySaleDetailSheet(context, sale, showSource: true),
        columns: [
          DataPanelColumn(
            label: 'Transaction & OS #',
            flex: 3,
            cell: (sale) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.transactionNo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: StitchColors.primary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
                Text(
                  sale.orNumber.isNotEmpty
                      ? '${sale.orNumber} · ${formatDateTime(sale.date)}'
                      : formatDateTime(sale.date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          DataPanelColumn(
            label: 'OR #',
            flex: 2,
            cell: (sale) => _isTagged(sale)
                ? StitchPill(
                    label: sale.invoiceNo!.trim(),
                    tone: StitchTone.primary,
                  )
                : const StitchPill(
                    label: 'Order Slip',
                    tone: StitchTone.neutral,
                  ),
          ),
          DataPanelColumn(
            label: 'Customer',
            flex: 2,
            cell: (sale) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.customer,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (sale.cashier.isNotEmpty)
                  Text(
                    sale.cashier,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
          DataPanelColumn(
            label: 'Items Summary',
            flex: 3,
            cell: (sale) => Text(
              _itemsSummary(sale),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          DataPanelColumn(
            label: 'Payment',
            flex: 2,
            cell: (sale) => StitchPill(
              label: sale.paymentMethod.isEmpty
                  ? 'No payment'
                  : sale.paymentMethod,
              tone: sale.creditSale ? StitchTone.warning : StitchTone.neutral,
            ),
          ),
          DataPanelColumn(
            label: 'Total',
            flex: 2,
            numeric: true,
            cell: (sale) => Text(
              formatPeso(sale.total),
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: StitchColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          DataPanelColumn(
            label: 'Status',
            flex: 2,
            cell: (sale) => StatusBadge(
              label: sale.displayStatusLabel,
              tone: sale.isAwaitingBodega
                  ? StatusTone.warning
                  : switch (sale.status) {
                      InventorySaleStatus.completed => StatusTone.success,
                      InventorySaleStatus.refunded => StatusTone.warning,
                      InventorySaleStatus.voided => StatusTone.error,
                    },
            ),
          ),
          DataPanelColumn(
            label: 'Inspect',
            flex: 1,
            cell: (sale) => Tooltip(
              message: 'View full transaction & items',
              child: IconButton(
                onPressed: () => showInventorySaleDetailSheet(
                  context,
                  sale,
                  showSource: true,
                ),
                icon: const Icon(
                  Icons.visibility_outlined,
                  size: 18,
                  color: StitchColors.primary,
                ),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
