import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product_tracking.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_stock_status_badge.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    // Stock, price, cost and location all live outside the variant now: stock on
    // batches, price on the selling unit, cost on the newest batch, location in
    // the local hint store. Decision 02 / 08 / 10.
    final inventory = context.read<InventoryViewmodel>();

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
                                status: inventory.statusForVariant(variant.id),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Wrap(
                            spacing: AppSpacing.xl,
                            runSpacing: AppSpacing.sm,
                            children: [
                              Text('Barcode: ${variant.barcode}'),
                              Text('Unit: ${variant.baseUomCode}'),
                              Text(
                                'Cost: ₱${(inventory.costFor(variant.id) ?? 0).toStringAsFixed(2)}',
                              ),
                              Text(
                                'Selling: ₱${(inventory.priceFor(variant.id) ?? 0).toStringAsFixed(2)}',
                              ),
                              Text(
                                'Stock: ${inventory.stockOnHandFor(variant.id).toStringAsFixed(0)}',
                              ),
                              Text(
                                'Reorder: ${variant.minStockThreshold.toStringAsFixed(0)}',
                              ),
                              Text(
                                'Location: ${inventory.locationHintFor(variant.id)}',
                              ),
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
