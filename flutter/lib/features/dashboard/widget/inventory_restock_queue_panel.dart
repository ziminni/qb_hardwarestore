import 'package:client/data/models/inventory.dart';
import 'package:client/features/dashboard/widget/inventory_dashboard_quantity.dart';
import 'package:client/features/dashboard/widget/inventory_panel_header.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// One variant that needs restocking, with the numbers the decision needs.
class InventoryRestockRow {
  const InventoryRestockRow({
    required this.variantId,
    required this.item,
    required this.onHand,
    required this.threshold,
    required this.status,
  });

  final int variantId;

  /// Product and variant together, the way a stock manager says it.
  final String item;
  final double onHand;
  final double threshold;
  final InventoryStockStatus status;
}

/// What needs restocking, most urgent first, as the shared [DataPanel].
///
/// The dashboard's job is "what needs me", so this is the main panel. The
/// ranking is the page's (it reads the viewmodel's stock); the panel only draws.
/// Rows are capped by the caller and the overflow says how many were cut, so a
/// silent `take(5)` can never hide a zero-stock variant again.
class InventoryRestockQueuePanel extends StatelessWidget {
  const InventoryRestockQueuePanel({
    super.key,
    required this.rows,
    required this.total,
    required this.emptyMessage,
    required this.onViewAll,
    required this.onRowTap,
    this.isLoading = false,
  });

  final List<InventoryRestockRow> rows;

  /// How many variants need restocking in total, so the overflow can count what
  /// the panel does not show.
  final int total;
  final String emptyMessage;
  final VoidCallback onViewAll;
  final ValueChanged<InventoryRestockRow> onRowTap;

  /// Only for a first load with nothing to show: a spinner over rows that are
  /// already there would hide them.
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final hidden = total - rows.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InventoryPanelHeader(
          title: 'Restock queue',
          actionLabel: 'View all',
          onAction: onViewAll,
        ),
        const SizedBox(height: AppSpacing.md),
        DataPanel<InventoryRestockRow>(
          rows: rows,
          isLoading: isLoading,
          emptyMessage: emptyMessage,
          rowKey: (row) => ValueKey('InventoryRestockRow.${row.variantId}'),
          onRowTap: onRowTap,
          columns: [
            DataPanelColumn<InventoryRestockRow>(
              label: 'Item',
              // The row's reason to exist, so it takes the largest share: a long
              // product name shortens instead of pushing the numbers off.
              flex: 3,
              cell: (row) => Text(
                row.item,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            DataPanelColumn<InventoryRestockRow>(
              label: 'On hand',
              numeric: true,
              flex: 2,
              cell: (row) => Text(
                formatQuantity(row.onHand),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: row.onHand <= 0 ? AppColors.errorText : null,
                ),
              ),
            ),
            DataPanelColumn<InventoryRestockRow>(
              label: 'Reorder at',
              numeric: true,
              flex: 2,
              cell: (row) => Text(
                formatQuantity(row.threshold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            DataPanelColumn<InventoryRestockRow>(
              label: 'Status',
              flex: 2,
              cell: (row) => StatusBadge(
                label: _words(row.status),
                tone: row.status == InventoryStockStatus.outOfStock
                    ? StatusTone.error
                    : StatusTone.warning,
              ),
            ),
          ],
        ),
        if (hidden > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '+$hidden more need restocking',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  /// The words say it; the tint only hints at it (D18).
  String _words(InventoryStockStatus status) => switch (status) {
    InventoryStockStatus.inStock => 'In stock',
    InventoryStockStatus.lowStock => 'Low stock',
    InventoryStockStatus.outOfStock => 'Out of stock',
  };
}
