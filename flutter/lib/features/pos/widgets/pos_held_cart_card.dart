import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/held_cart.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:flutter/material.dart';

/// One parked basket, as a card on the held-transactions screen.
///
/// A held cart is a few facts a cashier compares at a glance: who it is for,
/// how big it is, what it is worth and how long ago it was parked. What it is
/// worth is the fact that tells two baskets for the same customer apart, so it
/// sits next to the line count, right aligned with tabular digits like every
/// other amount in the app.
///
/// The two actions are deliberately NOT equal: [onResume] is the filled button
/// because picking the basket back up is the expected move, and [onVoid] is a
/// quiet red text button because it destroys the basket (the caller confirms).
///
/// The actions follow the card's own text rather than sitting on the card's
/// bottom edge: AppPanel lays its child out with an unbounded height, so there
/// is nothing to push against inside a stretched grid row.
class PosHeldCartCard extends StatelessWidget {
  const PosHeldCartCard({
    super.key,
    required this.cart,
    required this.ageLabel,
    required this.onResume,
    required this.onVoid,
  });

  final HeldCart cart;

  /// How long ago the basket was parked, already worded by the caller
  /// ("12 min ago"): the clock is read once per build, not once per card.
  final String ageLabel;

  final VoidCallback onResume;
  final VoidCallback onVoid;

  @override
  Widget build(BuildContext context) {
    final note = cart.notes.trim();
    final itemCount = cart.itemCount;

    return AppPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            cart.customerLabel,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$itemCount item${itemCount == 1 ? '' : 's'}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                formatPeso(cart.total),
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Held $ageLabel by ${cart.cashierName}',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          // No placeholder when there is no note: a lone dash says nothing a
          // missing line does not, and dashes are out app-wide (D18).
          if (note.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontStyle: FontStyle.italic,
                color: AppColors.textPrimary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: onResume,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  child: const Text('Resume'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: onVoid,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.errorText,
                  minimumSize: const Size(0, 44),
                ),
                child: const Text('Void'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
