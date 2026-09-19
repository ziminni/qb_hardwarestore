import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

class ProductsBulkActions extends StatelessWidget {
  const ProductsBulkActions({
    super.key,
    required this.selectedCount,
    required this.onArchive,
    required this.onClear,
  });

  final int selectedCount;
  final VoidCallback onArchive;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.selected,
        border: Border.all(color: AppColors.brandGoldLight),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          const Icon(Icons.check_circle_outline, size: 18),
          Text(
            '$selectedCount selected',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: onArchive,
            icon: const Icon(Icons.archive_outlined, size: 17),
            label: const Text('Move to archive'),
          ),
          TextButton(onPressed: onClear, child: const Text('Clear selection')),
        ],
      ),
    );
  }
}
