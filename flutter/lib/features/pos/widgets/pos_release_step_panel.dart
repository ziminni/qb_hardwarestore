import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:flutter/material.dart';

/// One numbered step of the release counter: a gold number, the step's own
/// heading, then the step's body.
///
/// The screen used to give verify, review and the receipt the same weight, so a
/// clerk could not tell what the screen was waiting for. A step shows its place
/// in the flow even before it has anything to show ([pending]), which is what
/// makes the three of them read as a sequence instead of three unrelated cards.
class PosReleaseStepPanel extends StatelessWidget {
  const PosReleaseStepPanel({
    super.key,
    required this.step,
    required this.title,
    required this.child,
    this.pending = false,
  });

  /// The step's number, as it reads to the clerk (1, 2, 3).
  final int step;

  final String title;

  /// The step's body: the field, the requisition, or the receipt.
  final Widget child;

  /// Nothing to show yet. The number and heading stay, quieter, so the flow
  /// ahead is visible without pretending a step is done.
  final bool pending;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _StepNumber(step: step, pending: pending),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppTextStyles.cinzelFont,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: pending
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _StepNumber extends StatelessWidget {
  const _StepNumber({required this.step, required this.pending});

  final int step;
  final bool pending;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: pending ? AppColors.background : AppColors.brandGold,
        shape: BoxShape.circle,
        border: pending ? Border.all(color: AppColors.border) : null,
      ),
      child: Text(
        '$step',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: pending ? AppColors.textSecondary : AppColors.brandBlack,
        ),
      ),
    );
  }
}
