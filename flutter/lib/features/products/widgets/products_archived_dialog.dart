import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:flutter/material.dart';

class ProductsArchivedDialog extends StatelessWidget {
  const ProductsArchivedDialog({super.key, required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return AlertDialog(
      title: const Text('Archived products'),
      content: SizedBox(
        width: 680,
        child: products.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 40,
                      color: colors.outline,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'No archived products',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Products moved to the archive will appear here.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 480),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadii.small),
                        child: ProductsImage(
                          imageUrl: product.imageUrl,
                          width: 44,
                          height: 44,
                        ),
                      ),
                      title: Text(product.baseName),
                      subtitle: Text(
                        '${product.categoryName} · ${product.brandName} · ${product.variants.length} variant${product.variants.length == 1 ? '' : 's'}',
                      ),
                      trailing: const Chip(label: Text('Archived')),
                    );
                  },
                ),
              ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
