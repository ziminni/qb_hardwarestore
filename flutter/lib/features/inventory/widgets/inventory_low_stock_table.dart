import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// One alert about one variant, with the catalogue rows it names.
///
/// The ALERT is the row's identity, not the variant: the same variant can carry
/// a LOW_STOCK row and an OUT_OF_STOCK row at once (the server escalates without
/// closing the older one), and each is resolved separately.
class LowStockRow {
  const LowStockRow({
    required this.alert,
    required this.product,
    required this.variant,
  });

  final SystemAlert alert;
  final Product product;
  final ProductVariant variant;
}

/// The low-stock alerts as a table on a wide window and a stack of cards on a
/// narrow one, built on the shared [DataPanel].
///
/// The ten column `DataTable` this replaces scrolled sideways, so below about
/// 1300 px the two buttons the screen exists for ("Reorder" and "Resolve") sat
/// past the right edge, unreachable. Rows keep only what answers "how bad is
/// it", "how much is left", "how much do I order" and "do something about it".
///
/// The list is ORDERED BY URGENCY here rather than in the page: an out-of-stock
/// variant is what a stock manager acts on first, and a cleared alert is the one
/// row that needs nothing. The server sends its alerts in its own order.
class InventoryLowStockTable extends StatelessWidget {
  const InventoryLowStockTable({
    super.key,
    required this.rows,
    required this.inventory,
    required this.onReorder,
    required this.onResolve,
    required this.emptyMessage,
    this.isLoading = false,
  });

  final List<LowStockRow> rows;
  final InventoryViewmodel inventory;
  final void Function(Product product, ProductVariant variant) onReorder;

  /// Null when the caller may not resolve alerts (the roles the server admits
  /// are decided by the page, on the role CODE). A null callback removes the
  /// button rather than rendering one that would answer 403.
  final void Function(SystemAlert alert)? onResolve;

  /// Worded by the page: "the server has flagged nothing" and "your filter hides
  /// everything" are different facts.
  final String emptyMessage;

  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final ordered = [...rows]..sort(_byUrgency);

    return DataPanel<LowStockRow>(
      title: 'Low stock',
      count: ordered.length,
      rows: ordered,
      isLoading: isLoading,
      emptyMessage: emptyMessage,
      rowKey: (row) => ValueKey('InventoryLowStockTable.row.${row.alert.id}'),
      columns: [
        DataPanelColumn<LowStockRow>(
          label: 'Product',
          // The row's reason to exist, so it takes the largest share: a very
          // long product name shortens instead of pushing the actions off. One
          // share more and the actions column could not hold both buttons at
          // 1100 px.
          flex: 3,
          cell: (row) => _productCell(row),
        ),
        DataPanelColumn<LowStockRow>(
          label: 'On hand',
          numeric: true,
          flex: 2,
          // The count over its level, with a bar under both: the shortage is
          // readable before the number is. Two lines on purpose, so a seven
          // digit level never has to shorten. Both counts go through
          // `formatCount` (D7).
          cell: (row) => _onHandCell(row),
        ),
        DataPanelColumn<LowStockRow>(
          label: 'Status',
          flex: 2,
          cell: (row) => _statusCell(context, row),
        ),
        DataPanelColumn<LowStockRow>(
          label: 'Order',
          numeric: true,
          // What the Reorder button will ask for (`suggestedReorderQty`): fill
          // back to the maximum stock level, else the threshold, else 1. Two
          // shares, because a seven digit quantity was cut to "1,200,..." in
          // one.
          flex: 2,
          cell: (row) => Text(
            formatCount(inventory.suggestedReorderQty(row.variant.id).round()),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataPanelColumn<LowStockRow>(
          label: 'Actions',
          // The same share as the name: both buttons sit side by side here, and
          // one share narrower pushed "Resolve" past the window's right edge at
          // 1100 px, which is the defect this screen is fixing.
          flex: 3,
          cell: (row) => _actionsCell(row),
        ),
      ],
    );
  }

  Widget _productCell(LowStockRow row) {
    // A cleared alert is kept on screen only for the record, so it reads quieter
    // than the rows that still need work.
    final muted = row.alert.isResolved ? AppColors.textSecondary : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          row.product.baseName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w600, color: muted),
        ),
        Text(
          row.variant.variantName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _onHandCell(LowStockRow row) {
    final stock = inventory.stockOnHandFor(row.variant.id);
    final threshold = row.variant.minStockThreshold;
    final outOfStock = stock <= 0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            formatCount(stock.round()),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Text(
            'left of ${formatCount(threshold.round())}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        // Phase 9 F1 (decision 21 §4): the threshold is the shop-wide total, and
        // this line says which shelf holds what — "Store 3 · Bodega 2" — so a
        // reorder can see that the shortfall sits in one place.
        if (inventory.stockSplitLabelFor(row.variant.id).isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              inventory.stockSplitLabelFor(row.variant.id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xs + 2),
        // The bar takes whatever width the cell has: a table cell at 1100 px
        // and a card at 760 px both get a readable bar out of the same code.
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: _fill(stock, threshold),
            minHeight: 6,
            backgroundColor: AppColors.border,
            color: outOfStock ? AppColors.error : AppColors.warning,
          ),
        ),
      ],
    );
  }

  Widget _statusCell(BuildContext context, LowStockRow row) {
    final status = inventory.statusForVariant(row.variant.id);
    final resolvedAt = row.alert.resolvedAt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        StatusBadge(label: _words(status), tone: _tone(status)),
        if (row.alert.isResolved) ...[
          const SizedBox(height: AppSpacing.xs),
          // Two lines on purpose: the name of the person and the time each get
          // their own width instead of shortening into "Resolved by A...".
          Text(
            'Resolved by '
            '${row.alert.resolvedByName.isEmpty ? 'a manager' : row.alert.resolvedByName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            resolvedAt == null
                ? 'Time not recorded'
                : formatDateTime(resolvedAt),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _actionsCell(LowStockRow row) {
    final resolve = onResolve;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FilledButton(
          // Compact sideways so both buttons fit one table cell at 1100 px;
          // the height is left to the theme, so the 44 px tap target stays.
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10),
          ),
          onPressed: () => onReorder(row.product, row.variant),
          child: const Text('Reorder'),
        ),
        // A resolved alert is not offered for resolving again.
        if (!row.alert.isResolved && resolve != null) ...[
          const SizedBox(width: AppSpacing.sm),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            onPressed: () => resolve(row.alert),
            child: const Text('Resolve'),
          ),
        ],
      ],
    );
  }

  /// Out of stock first, then the shortest stock against its own level, then a
  /// cleared alert last. `minStockThreshold` is that level, so 2 of 10 comes
  /// before 12 of 30: both are low, the first is closer to nothing.
  int _byUrgency(LowStockRow a, LowStockRow b) {
    final cleared = _clearedRank(a).compareTo(_clearedRank(b));
    if (cleared != 0) return cleared;
    final empty = _emptyRank(a).compareTo(_emptyRank(b));
    if (empty != 0) return empty;
    final byFill =
        _fill(
          inventory.stockOnHandFor(a.variant.id),
          a.variant.minStockThreshold,
        ).compareTo(
          _fill(
            inventory.stockOnHandFor(b.variant.id),
            b.variant.minStockThreshold,
          ),
        );
    if (byFill != 0) return byFill;
    final byName = a.product.baseName.compareTo(b.product.baseName);
    return byName != 0
        ? byName
        : a.variant.variantName.compareTo(b.variant.variantName);
  }

  int _clearedRank(LowStockRow row) => row.alert.isResolved ? 1 : 0;

  int _emptyRank(LowStockRow row) =>
      inventory.stockOnHandFor(row.variant.id) <= 0 ? 0 : 1;

  /// How much of the reorder level is still on the shelf, 0 to 1. A variant with
  /// no level set counts as full: there is nothing to be short of.
  double _fill(double stock, double threshold) {
    if (stock <= 0) return 0;
    if (threshold <= 0) return 1;
    return (stock / threshold).clamp(0, 1).toDouble();
  }

  /// D18 and the card's own wording: the words say it, the tint only hints at
  /// it, and the words are a sentence ("Out of stock"), not a shouted label.
  String _words(InventoryStockStatus status) => switch (status) {
    InventoryStockStatus.inStock => 'In stock',
    InventoryStockStatus.lowStock => 'Low stock',
    InventoryStockStatus.outOfStock => 'Out of stock',
  };

  StatusTone _tone(InventoryStockStatus status) => switch (status) {
    InventoryStockStatus.inStock => StatusTone.success,
    InventoryStockStatus.lowStock => StatusTone.warning,
    InventoryStockStatus.outOfStock => StatusTone.error,
  };
}
