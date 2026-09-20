import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/category.dart';
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: category.isActive
          ? colors.surface
          : colors.surfaceContainerHighest.withValues(alpha: .55),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onView,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.selected,
                      borderRadius: BorderRadius.circular(AppRadii.small),
                    ),
                    child: const Icon(
                      Icons.category_outlined,
                      color: AppColors.brandGold,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (category.isActive
                                  ? AppColors.success
                                  : AppColors.disabled)
                              .withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      category.isActive ? 'Active' : 'Archived',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: category.isActive
                            ? AppColors.success
                            : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Category actions',
                    onSelected: (value) {
                      if (value == 'view') onView();
                      if (value == 'edit') onEdit();
                      if (value == 'archive') onArchive();
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'view', child: Text('View')),
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
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
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 42,
                child: Text(
                  category.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
              const Divider(height: AppSpacing.xxl),
              Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '$productCount ${productCount == 1 ? 'product' : 'products'}',
                    style: theme.textTheme.labelLarge,
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: onView,
                    child: const Text('View details'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
