import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/suppliers/widgets/purchases_status_badge.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';

/// One purchase order, read-only: what was ordered, what has arrived, and what
/// the lines cost.
///
/// The "Received x / y lines" summary counts LINES that are fully here, never
/// the sum of the quantities: one line's quantity is in bags and another's in
/// pieces, so adding them would be adding bags to pieces. A line that is only
/// part of the way in is named as such below its own quantity.
class PurchasesDetailsDialog extends StatelessWidget {
  const PurchasesDetailsDialog({super.key, required this.order});
  final PurchaseOrder order;

  /// Lines where everything that was ordered has arrived.
  int get _receivedLines => order.items
      .where((item) => item.receivedQuantity >= item.quantity)
      .length;

  /// Lines that have arrived in part, so more is still expected.
  bool get _hasPartialLine => order.items.any(
    (item) =>
        item.receivedQuantity > 0 && item.receivedQuantity < item.quantity,
  );

  String _lineQuantity(PurchaseItem item) {
    if (item.receivedQuantity >= item.quantity) {
      return 'Received ${formatQuantity(item.quantity)}';
    }
    return 'Received ${formatQuantity(item.receivedQuantity)} '
        'of ${formatQuantity(item.quantity)}';
  }

  @override
  Widget build(BuildContext context) {
    final hasPartial = _hasPartialLine;
    return AppDialog(
      icon: Icons.local_shipping_outlined,
      title: 'PO-${order.id}',
      subtitle: order.supplierName.isEmpty
          ? 'Purchase order'
          : order.supplierName,
      headerTrailing: PurchasesStatusBadge(status: order.status),
      width: 780,
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const DialogSectionLabel('Order'),
          DetailRow(label: 'Ordered on', value: formatDate(order.orderDate)),
          DetailRow(
            label: 'Expected delivery',
            value: order.expectedDelivery == null
                ? 'Not set'
                : formatDate(order.expectedDelivery!),
          ),
          DetailRow(
            label: 'Created by',
            value: order.createdBy.isEmpty ? 'Unknown' : order.createdBy,
          ),
          // D18: no bare dash for "no value".
          DetailRow(
            label: 'Notes',
            value: order.notes.isEmpty ? 'None' : order.notes,
          ),
          const SizedBox(height: AppSpacing.xl),
          DialogSectionLabel(
            'Lines',
            trailing: Text(
              'Received $_receivedLines / ${order.items.length} lines',
              style: AppTextStyles.labelMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          for (final item in order.items) _line(item),
          if (hasPartial)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                'A line counts as received only when all of it has arrived.',
                style: AppTextStyles.bodySmall,
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
          TotalBar(label: 'Order total', amount: order.total),
        ],
      ),
    );
  }

  Widget _line(PurchaseItem item) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.surfaceMuted)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // A live PO line carries only the variant name: `POItemSerializer`
                // sends no product name and no SKU (decision D-02). Joining an
                // empty product name would render a leading separator and an
                // empty SKU a doubled one, so both are dropped when absent
                // instead of inventing a label the server never sent.
                Text(
                  item.productName.isEmpty
                      ? item.variantName
                      : '${item.productName}: ${item.variantName}',
                  style: AppTextStyles.labelLarge,
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (item.sku.isNotEmpty) item.sku,
                    'Ordered ${formatQuantity(item.quantity)}',
                    _lineQuantity(item),
                  ].join(' · '),
                  style: AppTextStyles.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            formatPeso(item.subtotal),
            style: AppTextStyles.labelLarge.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
