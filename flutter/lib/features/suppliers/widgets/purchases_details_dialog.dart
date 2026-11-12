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
      return 'Received ${_qty(item.quantity, item)}';
    }
    return 'Received ${_qty(item.receivedQuantity, item)} '
        'of ${_qty(item.quantity, item)}';
  }

  /// A count with the unit the line is ordered in (`10 BAG`).
  ///
  /// A line from a server that predates units names none, and then the number is
  /// written alone: the unit is never guessed from the variant's other units.
  static String _qty(double value, PurchaseItem item) => item.uomCode.isEmpty
      ? formatQuantity(value)
      : '${formatQuantity(value)} ${item.uomCode}';

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
          // Phase 5 B2 money: the server's figures when the payload carried
          // them, and a sentence (never a bare zero) when it did not.
          if (order.hasServerTotals) ...[
            const DialogSectionLabel('Money'),
            DetailRow(
              label: 'Gross',
              value: formatPeso(order.grossAmount ?? order.total),
            ),
            DetailRow(
              label: 'Discount',
              value: formatPeso(order.discountAmount),
            ),
            DetailRow(
              label: 'Net',
              value: formatPeso(order.netAmount ?? order.displayTotal),
            ),
            DetailRow(
              label: 'VATable',
              value: formatPeso(order.vatableAmount ?? 0),
            ),
            DetailRow(
              // Item 9: totals can arrive without the rate snapshot. A missing
              // rate is plain "VAT" — never a 0% rate, and never a zero tax
              // standing in for a figure the server did not send.
              label: order.vatRate == null || order.vatRate == 0
                  ? 'VAT'
                  : 'VAT (${_percent(order.vatRate!)}%)',
              value: order.vatRate == null
                  ? (order.vatAmount == null
                        ? 'Not recorded'
                        : formatPeso(order.vatAmount!))
                  : order.vatRate == 0
                  ? 'Not VAT registered'
                  : formatPeso(order.vatAmount ?? 0),
            ),
            DetailRow(
              label: 'Prices include VAT',
              value: order.vatInclusive ? 'Yes' : 'No, VAT is added',
            ),
            const SizedBox(height: AppSpacing.xl),
          ] else
            const Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.lg),
              child: InfoBanner(
                message:
                    'This order predates the discount and VAT split, so only '
                    'the line total is on record for it.',
              ),
            ),
          // The server's total wins over re-adding the lines: it is what the
          // bills against this order will inherit.
          TotalBar(label: 'Order total', amount: order.displayTotal),
        ],
      ),
    );
  }

  /// `12` rather than `12.00`: a rate is written the way a shop writes it.
  static String _percent(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

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
                    'Ordered ${_qty(item.quantity, item)}',
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
