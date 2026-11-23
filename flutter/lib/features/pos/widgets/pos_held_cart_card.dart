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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.surfaceSunken,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.border),
                ),
                child: Text(
                  'Hold #${cart.id}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  formatDateTime(cart.createdAt.toLocal()),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
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
          if (cart.items.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in cart.items.take(3))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 1.5),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.productName.isNotEmpty
                                  ? '${formatQuantity(item.qty)} ${item.unitCode.isNotEmpty ? "${item.unitCode} " : "× "}${item.productName}'
                                  : '${formatQuantity(item.qty)} × Unit #${item.variantUom}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            formatPeso(item.subtotal),
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (cart.items.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '+${cart.items.length - 3} more item(s)',
                        style: const TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (cart.expiresAt case final expiresAt?) ...[
            const SizedBox(height: 6),
            Builder(
              builder: (context) {
                final remaining = expiresAt.difference(DateTime.now());
                final expired = cart.isExpired || remaining.isNegative;
                final label = expired
                    ? 'Reservation expired · stock released'
                    : remaining.inMinutes >= 60
                    ? 'Stock reserved · ${remaining.inHours}h '
                          '${remaining.inMinutes % 60}m left'
                    : 'Stock reserved · ${remaining.inMinutes}m left';
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: expired
                          ? AppColors.warningTint
                          : AppColors.successTint,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          expired
                              ? Icons.timer_off_outlined
                              : Icons.lock_clock_outlined,
                          size: 13,
                          color: expired
                              ? AppColors.warningText
                              : AppColors.successText,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: expired
                                ? AppColors.warningText
                                : AppColors.successText,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
          // No placeholder when there is no note: a lone dash says nothing a
          // missing line does not, and dashes are out app-wide (D18).
          if (note.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.brandGold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.brandGold.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.sticky_note_2_outlined,
                    size: 15,
                    color: AppColors.brandBlack,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
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
