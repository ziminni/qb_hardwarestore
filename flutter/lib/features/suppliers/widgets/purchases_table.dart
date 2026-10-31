import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/suppliers/widgets/purchases_status_badge.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:flutter/material.dart';

/// The purchase-order book, with the transitions the server allows.
///
/// Which action is offered is decided by the ORDER's status, because the server
/// is strict about it: `place/` only leaves DRAFT (`INVALID_PO_STATE` otherwise)
/// and `cancel/` refuses an order with goods already received
/// (`PO_HAS_RECEIPTS`). A button that could only produce a refusal is not
/// rendered at all.
///
/// The rows are the shared [DataPanel]: a table on a wide panel, cards under
/// 720 px of panel width. The nine column `DataTable` this replaces scrolled
/// sideways, so at 760 px the total and the row actions sat off the right edge.
class PurchasesTable extends StatelessWidget {
  const PurchasesTable({
    super.key,
    required this.orders,
    required this.onView,
    required this.onPlace,
    required this.onCancel,
    required this.onReceive,
    required this.emptyMessage,
    this.isLoading = false,
    this.error,
    this.onRetry,
  });

  final List<PurchaseOrder> orders;

  /// Opens the details dialog. The whole row is the tap target.
  final ValueChanged<PurchaseOrder> onView;
  final ValueChanged<PurchaseOrder> onPlace;
  final ValueChanged<PurchaseOrder> onCancel;

  /// Sends the reader to Receiving, where the goods are recorded.
  final ValueChanged<PurchaseOrder> onReceive;

  /// Worded by the page: "nothing loaded" and "nothing matches" differ.
  final String emptyMessage;

  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return DataPanel<PurchaseOrder>(
      rows: orders,
      isLoading: isLoading,
      error: error,
      onRetry: onRetry,
      emptyMessage: emptyMessage,
      onRowTap: onView,
      rowKey: (order) => ValueKey('PurchasesTable.row.${order.id}'),
      columns: [
        DataPanelColumn<PurchaseOrder>(
          label: 'PO',
          flex: 2,
          cell: (order) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'PO-${order.id}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                formatDate(order.orderDate),
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
        DataPanelColumn<PurchaseOrder>(
          label: 'Supplier',
          flex: 3,
          cell: (order) => Text(
            order.supplierName.isEmpty
                ? 'No supplier on file'
                : order.supplierName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataPanelColumn<PurchaseOrder>(
          label: 'Progress',
          flex: 2,
          cell: (order) => _PurchasesProgress(status: order.status),
        ),
        DataPanelColumn<PurchaseOrder>(
          label: 'Total',
          numeric: true,
          flex: 3,
          cell: (order) => Text(
            formatPeso(order.total),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataPanelColumn<PurchaseOrder>(
          label: 'Status',
          flex: 3,
          cell: (order) => PurchasesStatusBadge(status: order.status),
        ),
        DataPanelColumn<PurchaseOrder>(
          label: 'Actions',
          flex: 2,
          cell: (order) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (order.canPlace)
                IconButton(
                  tooltip: 'Place purchase order',
                  onPressed: () => onPlace(order),
                  icon: const Icon(Icons.send_outlined, size: 18),
                ),
              if (order.status == PurchaseStatus.ordered ||
                  order.status == PurchaseStatus.partial)
                IconButton(
                  tooltip: 'Receive purchase order',
                  onPressed: () => onReceive(order),
                  icon: const Icon(Icons.move_to_inbox_outlined, size: 18),
                ),
              if (order.canCancel)
                IconButton(
                  tooltip: 'Cancel purchase order',
                  onPressed: () => onCancel(order),
                  icon: const Icon(Icons.block_outlined, size: 18),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The four steps an order passes through, as four small bars: filled up to the
/// step the order has reached.
///
/// The badge next to it spells the status; this is the shape of the journey, so
/// the bar carries words only in its tooltip and its semantics label.
class _PurchasesProgress extends StatelessWidget {
  const _PurchasesProgress({required this.status});

  final PurchaseStatus status;

  static const List<String> _steps = <String>[
    'Draft',
    'Ordered',
    'Received',
    'In stock',
  ];

  /// How many of the four bars are filled. A cancelled order has none: it did
  /// not travel, whatever it had reached when it stopped.
  static int stepFor(PurchaseStatus status) => switch (status) {
    PurchaseStatus.draft => 1,
    PurchaseStatus.ordered => 2,
    PurchaseStatus.partial => 3,
    PurchaseStatus.complete => 4,
    PurchaseStatus.cancelled => 0,
  };

  static Color _fillFor(PurchaseStatus status) => switch (status) {
    PurchaseStatus.draft => AppColors.textSecondary,
    PurchaseStatus.ordered => AppColors.brandGold,
    PurchaseStatus.partial => AppColors.warning,
    PurchaseStatus.complete => AppColors.success,
    PurchaseStatus.cancelled => AppColors.disabled,
  };

  @override
  Widget build(BuildContext context) {
    final step = stepFor(status);
    final label = step == 0
        ? 'Cancelled before any goods were received'
        : '${_steps[step - 1]}, step $step of 4: ${_steps.join(', ')}';
    return Tooltip(
      message: label,
      child: Semantics(
        label: label,
        child: Row(
          children: [
            for (var index = 1; index <= _steps.length; index++) ...[
              if (index > 1) const SizedBox(width: 4),
              Expanded(
                child: Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: index <= step ? _fillFor(status) : AppColors.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
