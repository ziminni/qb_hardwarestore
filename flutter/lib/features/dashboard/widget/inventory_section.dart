import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:flutter/material.dart';

/// A titled card whose header may carry one action.
///
/// `onAction` is passed straight through, so a header with a label but no
/// callback renders the button **disabled** rather than enabled and inert
/// (Phase 3 Task 0). If a label has nothing behind it, delete the label.
class InventorySection extends StatelessWidget {
  const InventorySection({
    super.key,
    required this.title,
    required this.child,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.labelLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (actionLabel != null)
                TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ),
          const Divider(),
          child,
        ],
      ),
    );
  }
}
