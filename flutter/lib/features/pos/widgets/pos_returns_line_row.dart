import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/returns.dart';
import 'package:flutter/material.dart';

/// One selling unit on the original sale, with the till's stepper.
///
/// The stepper is capped at `remaining_qty` on BOTH ends: the plus button is
/// disabled at the cap, so the screen cannot offer an amount `process_return`
/// would refuse with `RETURN_QTY_EXCEEDED`. A line with nothing left is shown
/// DISABLED rather than hidden, because the cashier must see that the sale had
/// that line and it has already come back.
class PosReturnsLineRow extends StatelessWidget {
  const PosReturnsLineRow({
    super.key,
    required this.line,
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
  });

  final ReturnableLine line;

  /// What the cashier stepped up so far (0 until they touch it).
  final double quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  @override
  Widget build(BuildContext context) {
    final enabled = line.hasRemaining;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${line.name} (${line.uom})',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: enabled ? null : AppColors.textSecondary,
                  ),
                ),
                Text(
                  enabled
                      ? '${line.remainingQty} of ${line.soldQty} left · '
                            '${line.returnedQty} already returned · '
                            '${formatPeso(line.unitPrice)}'
                      : 'All ${line.soldQty} already returned',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          IconButton(
            onPressed: enabled && quantity > 0 ? onDecrement : null,
            icon: const Icon(Icons.remove_circle_outline),
            tooltip: 'One fewer',
          ),
          SizedBox(
            width: 44,
            child: Text(
              quantity.toStringAsFixed(0),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          IconButton(
            onPressed: enabled && quantity < line.remainingQty
                ? onIncrement
                : null,
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'One more',
          ),
        ],
      ),
    );
  }
}
