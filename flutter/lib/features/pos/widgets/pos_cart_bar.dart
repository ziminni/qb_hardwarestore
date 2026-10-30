import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The sale in one line, pinned under the products on a narrow window: how
/// many lines, the total, the way into the full cart, and Pay.
class PosCartBar extends StatelessWidget {
  const PosCartBar({
    super.key,
    required this.onViewCart,
    required this.onPayment,
  });

  final VoidCallback onViewCart;
  final VoidCallback onPayment;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PosTransactionViewmodel>();
    final empty = state.lines.isEmpty;
    return Material(
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
                    '${state.itemCount} line item(s)',
                    style: const TextStyle(
                      color: Color(0xFFD9D3C4),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    formatPeso(state.total),
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
            OutlinedButton(
              onPressed: onViewCart,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.brandWhite,
                side: const BorderSide(color: Color(0xFF5A554C)),
                minimumSize: const Size(0, 48),
              ),
              child: const Text('View cart'),
            ),
            const SizedBox(width: AppSpacing.sm),
            FilledButton(
              onPressed: empty ? null : onPayment,
              // The default disabled grey vanishes on the black bar; an empty
              // cart's Pay must still read as a (greyed) button.
              style: FilledButton.styleFrom(
                minimumSize: const Size(88, 48),
                disabledBackgroundColor: const Color(0xFF3A362F),
                disabledForegroundColor: const Color(0xFFA9A396),
              ),
              child: const Text('Pay'),
            ),
          ],
        ),
      ),
    );
  }
}
