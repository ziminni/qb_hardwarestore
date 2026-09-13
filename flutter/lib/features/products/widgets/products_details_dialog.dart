import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:client/features/products/widgets/products_status_badge.dart';
import 'package:flutter/material.dart';

class ProductsDetailsDialog extends StatelessWidget {
  const ProductsDetailsDialog({super.key, required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(product.baseName),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.small),
                child: ProductsImage(
                  imageUrl: product.imageUrl,
                  width: 160,
                  height: 120,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ProductsStatusBadge(isActive: product.isActive),
              const SizedBox(height: AppSpacing.lg),
              Text('Category', style: theme.textTheme.labelMedium),
              Text(product.categoryName),
              const SizedBox(height: AppSpacing.md),
              Text('Brand', style: theme.textTheme.labelMedium),
              Text(product.brandName),
              const SizedBox(height: AppSpacing.md),
              Text('Description', style: theme.textTheme.labelMedium),
              Text(
                product.description.isEmpty
                    ? 'No description provided.'
                    : product.description,
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Variants (${product.variants.length})',
                style: theme.textTheme.titleSmall,
              ),
              const Divider(),
              if (product.variants.isEmpty)
                const Text('No variants added yet.')
              else
                for (final variant in product.variants)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(variant.variantName),
                    subtitle: Text('Base unit: ${variant.baseUomCode}'),
                    trailing: ProductsStatusBadge(isActive: variant.isActive),
                  ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
