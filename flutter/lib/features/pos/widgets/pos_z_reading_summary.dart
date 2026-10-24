import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/shift.dart';
import 'package:flutter/material.dart';

/// The end-of-shift summary a cashier reads at the drawer.
///
/// One widget for both places it appears — the Shifts tab and the confirmation
/// after closing from the till — so the two can never disagree about what a
/// Z-reading says. Variance is called out on its own line because it is the one
/// number that means "count the drawer again".
///
/// [title] says WHICH shift the figures belong to. The Shifts tab shows a live
/// shift's running totals or the last closed shift's, and an unlabelled block of
/// money was read as the live drawer.
class PosZReadingSummary extends StatelessWidget {
  const PosZReadingSummary({
    super.key,
    required this.reading,
    this.title = 'Z-READING',
  });

  final ZReading reading;

  /// The heading above the figures, e.g. `This shift so far`.
  final String title;

  @override
  Widget build(BuildContext context) {
    final variance = reading.variance;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppSpacing.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: AppSpacing.md),
          _line(context, 'Transactions', '${reading.transactionCount}'),
          _line(
            context,
            'Gross sales',
            '₱${reading.grossSales.toStringAsFixed(2)}',
          ),
          _line(context, 'Cash', '₱${reading.cashSales.toStringAsFixed(2)}'),
          _line(context, 'Card', '₱${reading.cardSales.toStringAsFixed(2)}'),
          _line(context, 'GCash', '₱${reading.gcashSales.toStringAsFixed(2)}'),
          _line(
            context,
            'Expected drawer',
            '₱${reading.expectedDrawer.toStringAsFixed(2)}',
          ),
          if (variance != null)
            _line(
              context,
              'Variance',
              '₱${variance.toStringAsFixed(2)}',
              color: variance == 0 ? null : AppColors.error,
            ),
          // Advisory (Phase 3 Task 3): parked carts are NOT part of the drawer
          // arithmetic and never block a close, so the line appears only when
          // there are some. Printing "0" on every Z-reading would put a number
          // next to the money that has nothing to do with it.
          if (reading.heldCartCount > 0)
            _line(
              context,
              'Held carts',
              '${reading.heldCartCount}',
              color: AppColors.warning,
            ),
        ],
      ),
    );
  }

  Widget _line(
    BuildContext context,
    String label,
    String value, {
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
