import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// One row of the stock book: a variant and the product it belongs to.
typedef InventoryStockRow = ({Product product, ProductVariant variant});

/// The stock book as a table on a wide screen and a stack of cards on a narrow
/// one, built on the shared [DataPanel].
///
/// The ten column `DataTable` this replaces scrolled sideways, so the one action
/// on the row ("Adjust") sat past the right edge on a 1100 px laptop. Here the
/// row keeps only what answers "how much is left" and "change it": product and
/// variant, category, on hand, reorder level, status, Adjust. The barcode, the
/// unit and the shelf note moved into the row details sheet.
class InventoryStockTable extends StatelessWidget {
  const InventoryStockTable({
    super.key,
    required this.records,
    required this.inventory,
    required this.onAdjust,
    this.isLoading = false,
    this.error,
    this.onRetry,
  });

  final List<InventoryStockRow> records;
  final InventoryViewmodel inventory;
  final void Function(Product product, ProductVariant variant) onAdjust;
  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  /// The empty copy, verbatim: `inventory_stock_pages_load_test.dart` pins it
  /// and only a completed load may show it.
  static const emptyMessage = 'No stock records match these filters.';

  @override
  Widget build(BuildContext context) {
    return DataPanel<InventoryStockRow>(
      rows: records,
      isLoading: isLoading,
      error: error,
      onRetry: onRetry,
      emptyMessage: emptyMessage,
      rowKey: (row) => ValueKey('InventoryStockTable.row.${row.variant.id}'),
      onRowTap: (row) => _showRowDetails(context, row),
      columns: [
        DataPanelColumn<InventoryStockRow>(
          label: 'Product',
          cell: (row) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.product.baseName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                row.variant.variantName,
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
        DataPanelColumn<InventoryStockRow>(
          label: 'Category',
          cell: (row) => Text(
            row.product.categoryName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataPanelColumn<InventoryStockRow>(
          label: 'On hand',
          numeric: true,
          // The unit rides along as a smaller, quieter run of the same line:
          // spelled at the number's size, a seven digit quantity plus "CU.M"
          // pushed the column past its width and cut the digits themselves.
          cell: (row) => Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: formatCount(
                    inventory.stockOnHandFor(row.variant.id).round(),
                  ),
                ),
                TextSpan(
                  text: ' ${row.variant.baseUomCode}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataPanelColumn<InventoryStockRow>(
          label: 'Reorder level',
          numeric: true,
          cell: (row) => Text(
            formatCount(row.variant.minStockThreshold.round()),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataPanelColumn<InventoryStockRow>(
          label: 'Status',
          cell: (row) {
            final status = inventory.statusForVariant(row.variant.id);
            return StatusBadge(label: status.label, tone: _toneFor(status));
          },
        ),
        DataPanelColumn<InventoryStockRow>(
          label: 'Adjust',
          cell: (row) => OutlinedButton.icon(
            onPressed: () => onAdjust(row.product, row.variant),
            icon: const Icon(Icons.tune, size: 16),
            label: const Text('Adjust'),
          ),
        ),
      ],
    );
  }

  void _showRowDetails(BuildContext context, InventoryStockRow row) {
    showDialog<void>(
      context: context,
      builder: (_) =>
          _InventoryStockDetailsDialog(row: row, inventory: inventory),
    );
  }
}

StatusTone _toneFor(InventoryStockStatus status) => switch (status) {
  InventoryStockStatus.inStock => StatusTone.success,
  InventoryStockStatus.lowStock => StatusTone.warning,
  InventoryStockStatus.outOfStock => StatusTone.error,
};

/// The identifiers that do not fit a row: barcode, unit and the shelf note.
class _InventoryStockDetailsDialog extends StatelessWidget {
  const _InventoryStockDetailsDialog({
    required this.row,
    required this.inventory,
  });

  final InventoryStockRow row;
  final InventoryViewmodel inventory;

  @override
  Widget build(BuildContext context) {
    final barcode = inventory.barcodeFor(row.variant.id);
    final note = inventory.locationHintFor(row.variant.id);
    return AlertDialog(
      title: Text(row.product.baseName),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              row.variant.variantName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            _line('Barcode', barcode.isEmpty ? 'No barcode recorded' : barcode),
            _line('Unit', row.variant.baseUomCode),
            // D9: the note is kept on this computer, not on the server.
            _line(
              'Shelf note (this computer)',
              note.isEmpty ? 'No shelf note yet' : note,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _line(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 190,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
