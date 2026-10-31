import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/features/dashboard/widget/inventory_panel_header.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:flutter/material.dart';

/// One recorded adjustment with the item name the wire does not carry.
class InventoryAdjustmentRow {
  const InventoryAdjustmentRow({required this.adjustment, required this.item});

  final StockAdjustment adjustment;

  /// Product and variant resolved from the catalogue. `StockAdjustmentSerializer`
  /// sends a variant id only.
  final String item;
}

/// The most recent stock adjustments (D2).
///
/// This panel used to be "Recent stock movements" and rendered the viewmodel's
/// flattened movements, which are the adjustments projected into a movement
/// shape: no types, invented before/after values, and a panel that could still
/// say "No movements recorded." after a day of sales and deliveries. It now
/// reads `InventoryViewModel.adjustments` directly, so what it shows is what the
/// server recorded: a type, a signed delta and the note the clerk wrote.
class InventoryRecentAdjustmentsPanel extends StatelessWidget {
  const InventoryRecentAdjustmentsPanel({
    super.key,
    required this.rows,
    required this.emptyMessage,
    required this.onViewAll,
    required this.onRowTap,
  });

  /// Newest first, already capped by the page.
  final List<InventoryAdjustmentRow> rows;
  final String emptyMessage;
  final VoidCallback onViewAll;
  final ValueChanged<InventoryAdjustmentRow> onRowTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InventoryPanelHeader(
          title: 'Recent adjustments',
          actionLabel: 'View all',
          onAction: onViewAll,
        ),
        const SizedBox(height: AppSpacing.md),
        DataPanel<InventoryAdjustmentRow>(
          rows: rows,
          emptyMessage: emptyMessage,
          rowKey: (row) => ValueKey('InventoryAdjustment.${row.adjustment.id}'),
          onRowTap: onRowTap,
          columns: [
            DataPanelColumn<InventoryAdjustmentRow>(
              label: 'Item',
              flex: 3,
              cell: (row) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.item,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    // D18: no note is a fact, so it is a word, not a dash.
                    row.adjustment.remarks.isEmpty
                        ? 'No note'
                        : row.adjustment.remarks,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            DataPanelColumn<InventoryAdjustmentRow>(
              label: 'Type',
              flex: 2,
              cell: (row) => Text(
                row.adjustment.adjustmentType.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DataPanelColumn<InventoryAdjustmentRow>(
              label: 'When',
              flex: 2,
              // Date AND time (D6): two adjustments on the same day are the
              // normal case, and a date alone makes them look identical.
              cell: (row) => Text(
                formatDateTime(row.adjustment.timestamp),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            DataPanelColumn<InventoryAdjustmentRow>(
              label: 'Change',
              numeric: true,
              flex: 2,
              cell: (row) => Text(
                formatSignedQuantity(row.adjustment.quantityAdjusted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: row.adjustment.quantityAdjusted < 0
                      ? AppColors.errorText
                      : AppColors.successText,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
