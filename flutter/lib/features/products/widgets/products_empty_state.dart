import 'package:client/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

class ProductsEmptyState extends StatelessWidget {
  const ProductsEmptyState({super.key, required this.onClearFilters});

  final VoidCallback onClearFilters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 40, color: colors.outline),
          const SizedBox(height: AppSpacing.md),
          Text('No products found', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Try changing or clearing the current filters.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton(
            onPressed: onClearFilters,
            child: const Text('Clear filters'),
          ),
        ],
      ),
    );
  }
}
