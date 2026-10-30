import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';

class ProductsArchivedDialog extends StatelessWidget {
  const ProductsArchivedDialog({super.key, required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.archive_outlined,
      title: 'Archived products',
      subtitle:
          '${products.length} ${products.length == 1 ? 'product' : 'products'} removed from the catalog',
      width: 700,
      content: products.isEmpty
          ? const EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'No archived products',
              message: 'Products moved to the archive will appear here.',
            )
          : Column(
              children: [
                for (final product in products)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.md,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: AppColors.surfaceMuted),
                      ),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.small),
                          child: ProductsImage(
                            imageUrl: product.imageUrl,
                            width: 44,
                            height: 44,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                product.baseName,
                                style: AppTextStyles.labelLarge,
                              ),
                              Text(
                                '${product.categoryName} · ${product.brandName} · ${product.variants.length} variant${product.variants.length == 1 ? '' : 's'}',
                                style: AppTextStyles.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        const StatusPill(
                          label: 'Archived',
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
              ],
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
