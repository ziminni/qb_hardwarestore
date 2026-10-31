import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/category.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// One category in the grid: what it is called, whether it is still offered,
/// and how many products are filed under it.
///
/// The count is the point of the card (K3): archiving a category without
/// knowing what sits under it was a blind choice. It is read off the catalogue
/// the store already loaded, so it costs no request of its own.
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

  /// Products filed under this category in the loaded catalogue.
  final int productCount;

  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final productsLabel =
        '${formatCount(productCount)} '
        '${productCount == 1 ? 'product' : 'products'}';

    return AppPanel(
      // The whole card opens the details, so the tap area is the panel itself
      // and not the "View details" label inside it.
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onView,
          borderRadius: BorderRadius.circular(AppRadii.medium),
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
                      color: AppColors.brandGoldText,
                    ),
                  ),
                  const Spacer(),
                  StatusBadge(
                    label: category.isActive ? 'Active' : 'Archived',
                    tone: category.isActive
                        ? StatusTone.success
                        : StatusTone.neutral,
                  ),
                  // The menu is the card's action list. Archive and restore are
                  // the same PATCH with the other flag: DELETE answers 405, so a
                  // category is never removed.
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
                        )
                      else
                        const PopupMenuItem(
                          value: 'archive',
                          child: Text('Restore'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                category.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Divider(height: AppSpacing.xxl),
              // Count on the left, the way into the details on the right. The
              // count is the number a clerk checks before archiving.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 18,
                        color: category.isActive
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        productsLabel,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: category.isActive
                              ? AppColors.textPrimary
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: onView,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      foregroundColor: AppColors.brandGoldText,
                    ),
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
