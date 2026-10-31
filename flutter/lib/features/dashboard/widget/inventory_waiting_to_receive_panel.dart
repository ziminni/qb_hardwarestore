import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/dashboard/widget/inventory_panel_header.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// Deliveries the stock manager is still waiting for.
///
/// Reads the purchase orders the Purchasing screens already load
/// (`GET /api/v1/purchase-orders/`), and keeps only an ORDERED or PARTIAL order:
/// those are the two states the server will accept a receipt against, so this
/// panel can never point at a delivery that will be refused. The supplier name
/// is the viewmodel's join on the supplier id, and an unmatched id stays blank
/// here rather than guessed.
class InventoryWaitingToReceivePanel extends StatelessWidget {
  const InventoryWaitingToReceivePanel({
    super.key,
    required this.orders,
    required this.total,
    required this.emptyMessage,
    required this.onViewAll,
    required this.onRowTap,
    this.isLoading = false,
    this.error,
    this.onRetry,
  });

  /// Already filtered to ORDERED and PARTIAL by the page, soonest expected
  /// delivery first.
  final List<PurchaseOrder> orders;

  /// How many orders are waiting in total, so the overflow can count the ones
  /// the panel does not show.
  final int total;
  final String emptyMessage;
  final VoidCallback onViewAll;
  final ValueChanged<PurchaseOrder> onRowTap;
  final bool isLoading;

  /// The purchase order read's own failure. It is separate from the catalogue's:
  /// a dead purchase order endpoint must not blank the restock queue.
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final hidden = total - orders.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InventoryPanelHeader(
          title: 'Waiting to receive',
          actionLabel: 'View all',
          onAction: onViewAll,
        ),
        const SizedBox(height: AppSpacing.md),
        DataPanel<PurchaseOrder>(
          rows: orders,
          isLoading: isLoading,
          error: error,
          onRetry: onRetry,
          emptyMessage: emptyMessage,
          rowKey: (order) => ValueKey('InventoryWaitingToReceive.${order.id}'),
          onRowTap: onRowTap,
          columns: [
            DataPanelColumn<PurchaseOrder>(
              label: 'Order',
              flex: 2,
              cell: (order) => Text(
                'PO-${order.id}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            DataPanelColumn<PurchaseOrder>(
              label: 'Supplier',
              flex: 3,
              cell: (order) => Text(
                // D18: a missing name says why it is missing instead of a dash.
                order.supplierName.isEmpty
                    ? 'Supplier not listed'
                    : order.supplierName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            DataPanelColumn<PurchaseOrder>(
              label: 'Expected',
              flex: 2,
              cell: (order) => Text(
                order.expectedDelivery == null
                    ? 'Not set'
                    : formatDate(order.expectedDelivery!),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            DataPanelColumn<PurchaseOrder>(
              label: 'Still due',
              numeric: true,
              flex: 2,
              // What is on order minus what has already arrived: a real number
              // from the order's own lines, not a reorder suggestion.
              cell: (order) => Text(
                formatQuantity(order.orderedQuantity - order.receivedQuantity),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            DataPanelColumn<PurchaseOrder>(
              label: 'Status',
              flex: 2,
              cell: (order) => StatusBadge(
                label: order.status == PurchaseStatus.partial
                    ? 'Part received'
                    : 'Waiting',
                tone: order.status == PurchaseStatus.partial
                    ? StatusTone.info
                    : StatusTone.warning,
              ),
            ),
          ],
        ),
        if (hidden > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            '+$hidden more waiting to be received',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }
}
