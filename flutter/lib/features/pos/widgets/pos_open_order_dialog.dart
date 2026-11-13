import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/services/pos_service.dart';
import 'package:flutter/material.dart';

/// The counter's list of orders it may still ring (Phase 7 F2, decision 19 #3/#4).
///
/// A cashier opens an order like a resumed held cart: the till loads what is
/// LEFT of it, at the prices the customer agreed. This dialog is the choice of
/// WHICH order, and it says what the till is about to find - the remaining
/// quantity per line, the agreed unit price, and whether the shelf can cover it
/// right now.
///
/// It returns the chosen [PosOpenOrder]; the page hands it to the viewmodel,
/// which owns the cart. The dialog itself talks to nobody.
class PosOpenOrderDialog extends StatelessWidget {
  const PosOpenOrderDialog({
    super.key,
    required this.orders,
    this.customerName,
    this.productName,
    this.loadError,
    this.onRetry,
  });

  final List<PosOpenOrder> orders;

  /// The customer's name when the caller knows it; a null answer falls back to
  /// the order number rather than printing a bare id.
  final String Function(int customerId)? customerName;

  /// The catalogue's name for a selling unit, so a line reads as a product.
  final String Function(int variantUomId)? productName;

  /// Why the list could not be read, if it could not.
  final String? loadError;

  /// Re-reads the list. Shown only with [loadError].
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Open orders'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (loadError case final message?) ...[
                Text(
                  message,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                if (onRetry != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: onRetry,
                      child: const Text('Try again'),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
              ],
              if (orders.isEmpty && loadError == null)
                const Text(
                  'No confirmed orders are waiting. An order appears here once '
                  'it is saved on the Sales screen.',
                ),
              for (final order in orders) _orderCard(context, order),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }

  Widget _orderCard(BuildContext context, PosOpenOrder order) {
    final who = customerName?.call(order.customerId) ?? 'Order ${order.number}';
    return Card(
      key: ValueKey('pos-open-order-${order.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${order.number} · $who',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  order.status == 'PARTIAL'
                      ? 'Partially fulfilled'
                      : 'Confirmed',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final line in order.lines)
              if (line.remainingQty > 0) _lineRow(line),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'To ring: ${formatPeso(order.remainingTotal)}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  key: ValueKey('pos-open-order-choose-${order.id}'),
                  onPressed: () => Navigator.pop(context, order),
                  child: const Text('Ring this order'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineRow(PosOpenOrderLine line) {
    final name =
        productName?.call(line.variantUomId) ?? 'Item ${line.variantUomId}';
    final hint = line.stockHint;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(name)),
          Text(
            '${_qty(line.remainingQty)} × ${formatPeso(line.unitPrice)}',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          if (hint != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              hint,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: hint == 'Enough in stock'
                    ? AppColors.successText
                    : AppColors.warningText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// A whole count without decimals, a measured one with them.
  static String _qty(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}
