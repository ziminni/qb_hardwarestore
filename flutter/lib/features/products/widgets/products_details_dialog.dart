import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product_tracking.dart';
import 'package:client/features/inventory/widgets/inventory_stock_status_badge.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:flutter/material.dart';

class ProductsDetailsDialog extends StatelessWidget {
  const ProductsDetailsDialog({
    super.key,
    required this.product,
    this.movements = const [],
    this.tracking,
  });

  final Product product;
  final List<InventoryMovement> movements;
  final ProductTrackingConfiguration? tracking;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(product.baseName),
      content: SizedBox(
        width: 780,
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
              if (tracking != null) ...[
                const SizedBox(height: AppSpacing.xl),
                Text('Inventory Tracking', style: theme.textTheme.titleSmall),
                const Divider(),
                Wrap(
                  spacing: AppSpacing.xl,
                  runSpacing: AppSpacing.sm,
                  children: [
                    Text('Method: ${tracking!.method.label}'),
                    Text('Base unit: ${tracking!.baseUnit}'),
                    Text('Stock form: ${tracking!.stockForm.label}'),
                    Text(
                      'Total available: ${tracking!.totalBaseQuantity.toStringAsFixed(3)} ${tracking!.baseUnit}',
                    ),
                    Text('Location: ${tracking!.storageLocation}'),
                  ],
                ),
                if (tracking!.physicalPieces.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text('Physical pieces', style: theme.textTheme.labelLarge),
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: tracking!.physicalPieces.length,
                      itemBuilder: (context, index) {
                        final remaining = tracking!.physicalPieces[index];
                        final full =
                            (remaining - tracking!.standardLength).abs() <
                            .0001;
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            'Piece #${(index + 1).toString().padLeft(3, '0')}',
                          ),
                          trailing: Text(
                            '${remaining.toStringAsFixed(3)} ${tracking!.baseUnit} · ${full ? 'Full' : 'Cut'}',
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ],
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
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  variant.variantName,
                                  style: theme.textTheme.titleSmall,
                                ),
                              ),
                              InventoryStockStatusBadge(
                                status: variant.currentStock <= 0
                                    ? InventoryStockStatus.outOfStock
                                    : variant.currentStock <=
                                          variant.reorderLevel
                                    ? InventoryStockStatus.lowStock
                                    : InventoryStockStatus.inStock,
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.xl,
                            runSpacing: AppSpacing.sm,
                            children: [
                              Text('SKU: ${variant.sku}'),
                              Text('QR: ${variant.qrIdentifier}'),
                              Text('Unit: ${variant.baseUomCode}'),
                              Text(
                                'Cost: ₱${variant.costPrice.toStringAsFixed(2)}',
                              ),
                              Text(
                                'Selling: ₱${variant.sellingPrice.toStringAsFixed(2)}',
                              ),
                              Text(
                                'Stock: ${variant.currentStock.toStringAsFixed(0)}',
                              ),
                              Text(
                                'Reorder: ${variant.reorderLevel.toStringAsFixed(0)}',
                              ),
                              Text('Location: ${variant.storageLocation}'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Stock History (${movements.length})',
                style: theme.textTheme.titleSmall,
              ),
              const Divider(),
              if (movements.isEmpty)
                const Text('No stock history yet.')
              else
                for (final movement in movements.take(5))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(movement.type.label),
                    subtitle: Text(
                      '${movement.reference} · ${movement.reason}',
                    ),
                    trailing: Text(
                      '${movement.quantityChange > 0 ? '+' : ''}${movement.quantityChange.toStringAsFixed(0)}',
                    ),
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
