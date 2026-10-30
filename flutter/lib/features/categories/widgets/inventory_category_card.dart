import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/data/models/category.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';

class InventoryCategoryCard extends StatelessWidget {
  const InventoryCategoryCard({
    super.key,
    required this.category,
    required this.productCount,
    required this.onView,
    required this.onEdit,
    required this.onArchive,
  });

  final Category category;
  final int productCount;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: category.isActive
          ? AppColors.cardBackground
          : AppColors.surfaceSunken,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onView,
        hoverColor: AppColors.selected.withValues(alpha: 0.35),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 3,
              color: category.isActive ? AppColors.brandGold : AppColors.border,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg + 2,
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const HexIconBadge(icon: Icons.category_outlined),
                      const Spacer(),
                      StatusPill(
                        label: category.isActive ? 'Active' : 'Archived',
                        color: category.isActive
                            ? AppColors.success
                            : AppColors.textSecondary,
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Category actions',
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (value) {
                          if (value == 'view') onView();
                          if (value == 'edit') onEdit();
                          if (value == 'archive') onArchive();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'view',
                            child: Text('View'),
                          ),
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          if (category.isActive)
                            const PopupMenuItem(
                              value: 'archive',
                              child: Text('Archive'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    category.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.h4.copyWith(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.md),
                    child: SizedBox(
                      height: 40,
                      child: Text(
                        category.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.bodySmall.copyWith(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg + 2,
                AppSpacing.xs,
                AppSpacing.sm,
                AppSpacing.xs,
              ),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.inventory_2_outlined,
                    size: 16,
                    color: AppColors.brandGold,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '$productCount ${productCount == 1 ? 'product' : 'products'}',
                    style: AppTextStyles.labelLarge,
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: onView,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brandGold,
                    ),
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                    label: const Text('View details'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
