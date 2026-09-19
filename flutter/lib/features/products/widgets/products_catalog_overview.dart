import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

class ProductsCatalogOverview extends StatelessWidget {
  const ProductsCatalogOverview({
    super.key,
    required this.totalProducts,
    required this.totalVariants,
    required this.archivedProducts,
    required this.categoryCount,
    required this.brandCount,
    required this.lowStockVariants,
    required this.outOfStockVariants,
    required this.onShowAll,
    required this.onShowLowStock,
  });

  final int totalProducts;
  final int totalVariants;
  final int archivedProducts;
  final int categoryCount;
  final int brandCount;
  final int lowStockVariants;
  final int outOfStockVariants;
  final VoidCallback onShowAll;
  final VoidCallback onShowLowStock;

  Widget _metric({
    required BuildContext context,
    required String label,
    required String value,
    required String firstDetail,
    required String secondDetail,
    required VoidCallback onTap,
    Color? valueColor,
    Color? detailColor,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.small),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                value,
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: valueColor ?? colors.onSurface,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                firstDetail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: detailColor ?? colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                secondDetail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final metrics = [
      _metric(
        context: context,
        label: 'Total products',
        value: '$totalProducts',
        firstDetail: '$categoryCount categories',
        secondDetail: '$brandCount brands represented',
        onTap: onShowAll,
      ),
      _metric(
        context: context,
        label: 'Categories',
        value: '$categoryCount',
        firstDetail: '$totalProducts catalog products',
        secondDetail: 'Organized product groups',
        onTap: onShowAll,
      ),
      _metric(
        context: context,
        label: 'Product variants',
        value: '$totalVariants',
        firstDetail: '$lowStockVariants low stock',
        secondDetail: '$outOfStockVariants out of stock',
        onTap: onShowLowStock,
        detailColor: lowStockVariants == 0
            ? AppColors.success
            : AppColors.warning,
      ),
      _metric(
        context: context,
        label: 'Archived',
        value: '$archivedProducts',
        firstDetail: archivedProducts == 0
            ? 'Archive is empty'
            : '$archivedProducts removed from catalog',
        secondDetail: 'Not shown in the products table',
        onTap: onShowAll,
        detailColor: colors.onSurfaceVariant,
      ),
    ];

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Catalog overview',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'Product availability and catalog coverage',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Click a metric to view related records',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 920 ? 4 : 2;
              final width = constraints.maxWidth / columns;
              return Wrap(
                children: [
                  for (var index = 0; index < metrics.length; index++)
                    Container(
                      width: width,
                      constraints: const BoxConstraints(minHeight: 150),
                      decoration: BoxDecoration(
                        border: Border(
                          right: index % columns == columns - 1
                              ? BorderSide.none
                              : const BorderSide(color: AppColors.border),
                          bottom: columns == 2 && index < 2
                              ? const BorderSide(color: AppColors.border)
                              : BorderSide.none,
                        ),
                      ),
                      child: metrics[index],
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
