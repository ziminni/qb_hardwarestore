import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:flutter/material.dart';

/// The refund pinned to the bottom of a narrow window: the cash figure the
/// cashier hands over, and Confirm. Same idea as the till's cart bar (C7).
///
/// It shows the CASH refund as the big number because that is the money that
/// leaves the drawer; the return's full value sits above it so the split with
/// the utang stays visible while the cashier reads the amount out loud.
class PosReturnsBar extends StatelessWidget {
  const PosReturnsBar({
    super.key,
    required this.returnValue,
    required this.cashRefund,
    required this.canConfirm,
    required this.onConfirm,
  });

  /// Tests find the bar by this key: at a narrow width the Confirm button lives
  /// HERE and not in the Refund step, so the two can never both be on screen.
  static const barKey = ValueKey('pos-returns-bar');

  final double returnValue;
  final double cashRefund;
  final bool canConfirm;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Material(
      key: barKey,
      color: AppColors.brandBlack,
      borderRadius: BorderRadius.circular(AppRadii.medium),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Return value ${formatPeso(returnValue)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFD9D3C4),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Cash refund ${formatPeso(cashRefund)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.brandWhite,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: canConfirm ? onConfirm : null,
              // The default disabled grey vanishes on the black bar; an
              // incomplete return's Confirm must still read as a button.
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 48),
                disabledBackgroundColor: const Color(0xFF3A362F),
                disabledForegroundColor: const Color(0xFFA9A396),
              ),
              child: const Text('Confirm return'),
            ),
          ],
        ),
      ),
    );
  }
}
