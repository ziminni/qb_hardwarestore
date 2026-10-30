import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product_tracking.dart';
import 'package:client/features/inventory/widgets/inventory_stock_status_badge.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:client/features/products/widgets/products_status_badge.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/data_panel.dart';
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
    return AppDialog(
      icon: Icons.inventory_2_outlined,
      title: product.baseName,
      subtitle: '${product.categoryName} · ${product.brandName}',
      headerTrailing: ProductsStatusBadge(isActive: product.isActive),
      width: 800,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadii.medium),
                child: ProductsImage(
                  imageUrl: product.imageUrl,
                  width: 160,
                  height: 120,
                ),
              ),
              const SizedBox(width: AppSpacing.xl),
              Expanded(
                child: Column(
                  children: [
                    DetailRow(
                      label: 'Category',
                      value: product.categoryName,
                      labelWidth: 110,
                    ),
                    DetailRow(
                      label: 'Brand',
                      value: product.brandName,
                      labelWidth: 110,
                    ),
                    DetailRow(
                      label: 'Description',
                      value: product.description.isEmpty
                          ? 'No description provided.'
                          : product.description,
                      labelWidth: 110,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (tracking != null) ...[
            const SizedBox(height: AppSpacing.xl),
            const DialogSectionLabel('Inventory Tracking'),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                _SpecChip(label: 'Method', value: tracking!.method.label),
                _SpecChip(label: 'Base unit', value: tracking!.baseUnit),
                _SpecChip(
                  label: 'Stock form',
                  value: tracking!.stockForm.label,
                ),
                _SpecChip(
                  label: 'Total available',
                  value:
                      '${tracking!.totalBaseQuantity.toStringAsFixed(3)} ${tracking!.baseUnit}',
                ),
                _SpecChip(label: 'Location', value: tracking!.storageLocation),
              ],
            ),
            if (tracking!.physicalPieces.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text('Physical pieces', style: AppTextStyles.labelLarge),
              const SizedBox(height: AppSpacing.sm),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  itemCount: tracking!.physicalPieces.length,
                  itemBuilder: (context, index) {
                    final remaining = tracking!.physicalPieces[index];
                    final full =
                        (remaining - tracking!.standardLength).abs() < .0001;
                    return DetailRow(
                      label: 'Piece #${(index + 1).toString().padLeft(3, '0')}',
                      value:
                          '${remaining.toStringAsFixed(3)} ${tracking!.baseUnit} · ${full ? 'Full' : 'Cut'}',
                    );
                  },
                ),
              ),
            ],
          ],
          const SizedBox(height: AppSpacing.xl),
          DialogSectionLabel('Variants (${product.variants.length})'),
          if (product.variants.isEmpty)
            const EmptyState(
              icon: Icons.layers_outlined,
              title: 'No variants added yet.',
            )
          else
            for (final variant in product.variants)
              Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.md),
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.layers_outlined,
                          size: 18,
                          color: AppColors.brandGold,
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            variant.variantName,
                            style: AppTextStyles.labelLarge.copyWith(
                              fontSize: 15,
                            ),
                          ),
                        ),
                        InventoryStockStatusBadge(
                          status: variant.currentStock <= 0
                              ? InventoryStockStatus.outOfStock
                              : variant.currentStock <= variant.reorderLevel
                              ? InventoryStockStatus.lowStock
                              : InventoryStockStatus.inStock,
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        _SpecChip(label: 'SKU', value: variant.sku),
                        _SpecChip(
                          label: 'Barcode',
                          value: variant.qrIdentifier,
                        ),
                        _SpecChip(label: 'Unit', value: variant.baseUomCode),
                        _SpecChip(
                          label: 'Cost',
                          value: '₱${variant.costPrice.toStringAsFixed(2)}',
                        ),
                        _SpecChip(
                          label: 'Selling',
                          value: '₱${variant.sellingPrice.toStringAsFixed(2)}',
                        ),
                        _SpecChip(
                          label: 'Stock',
                          value: variant.currentStock.toStringAsFixed(0),
                        ),
                        _SpecChip(
                          label: 'Reorder',
                          value: variant.reorderLevel.toStringAsFixed(0),
                        ),
                        _SpecChip(
                          label: 'Location',
                          value: variant.storageLocation,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          const SizedBox(height: AppSpacing.lg),
          DialogSectionLabel('Stock History (${movements.length})'),
          if (movements.isEmpty)
            const EmptyState(
              icon: Icons.history_rounded,
              title: 'No stock history yet.',
            )
          else
            for (final movement in movements.take(5))
              LineItemTile(
                icon: movement.quantityChange > 0
                    ? Icons.south_west
                    : Icons.north_east,
                title: movement.type.label,
                subtitle: '${movement.reference} · ${movement.reason}',
                amount:
                    '${movement.quantityChange > 0 ? '+' : ''}${movement.quantityChange.toStringAsFixed(0)}',
              ),
        ],
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

class _SpecChip extends StatelessWidget {
  const _SpecChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadii.small),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: AppTextStyles.labelSmall.copyWith(
              fontSize: 9,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 2),
          Text(value, style: AppTextStyles.labelMedium),
        ],
      ),
    );
  }
}
