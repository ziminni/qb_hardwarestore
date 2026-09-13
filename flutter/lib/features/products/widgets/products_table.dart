import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/products/widgets/products_empty_state.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:client/features/products/widgets/products_pagination.dart';
import 'package:client/features/products/widgets/products_status_badge.dart';
import 'package:flutter/material.dart';

class ProductsTable extends StatelessWidget {
  const ProductsTable({
    super.key,
    required this.products,
    required this.selectedProductIds,
    required this.firstItem,
    required this.lastItem,
    required this.totalItems,
    required this.currentPage,
    required this.totalPages,
    required this.rowsPerPage,
    required this.onSelectProduct,
    required this.onSelectAll,
    required this.onViewProduct,
    required this.onEditProduct,
    required this.onToggleStatus,
    required this.onClearFilters,
    required this.onPageChanged,
    required this.onRowsPerPageChanged,
  });

  final List<Product> products;
  final Set<int> selectedProductIds;
  final int firstItem;
  final int lastItem;
  final int totalItems;
  final int currentPage;
  final int totalPages;
  final int rowsPerPage;
  final void Function(int productId, bool selected) onSelectProduct;
  final ValueChanged<bool> onSelectAll;
  final ValueChanged<Product> onViewProduct;
  final ValueChanged<Product> onEditProduct;
  final ValueChanged<Product> onToggleStatus;
  final VoidCallback onClearFilters;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRowsPerPageChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final allVisibleSelected =
        products.isNotEmpty &&
        products.every((product) => selectedProductIds.contains(product.id));

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
          if (products.isEmpty)
            ProductsEmptyState(onClearFilters: onClearFilters)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  colors.secondaryContainer,
                ),
                columns: [
                  DataColumn(
                    label: Checkbox(
                      value: allVisibleSelected,
                      onChanged: (value) => onSelectAll(value ?? false),
                    ),
                  ),
                  const DataColumn(label: Text('Product')),
                  const DataColumn(label: Text('Category')),
                  const DataColumn(label: Text('Brand')),
                  const DataColumn(label: Text('Variants')),
                  const DataColumn(label: Text('Status')),
                  const DataColumn(label: Text('Actions')),
                ],
                rows: products.map((product) {
                  return DataRow(
                    selected: selectedProductIds.contains(product.id),
                    cells: [
                      DataCell(
                        Checkbox(
                          value: selectedProductIds.contains(product.id),
                          onChanged: (value) =>
                              onSelectProduct(product.id, value ?? false),
                        ),
                      ),
                      DataCell(
                        SizedBox(
                          width: 280,
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  AppRadii.small,
                                ),
                                child: ProductsImage(
                                  imageUrl: product.imageUrl,
                                  width: 40,
                                  height: 40,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      product.baseName,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    Text(
                                      product.description,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      DataCell(Text(product.categoryName)),
                      DataCell(Text(product.brandName)),
                      DataCell(Text('${product.variants.length}')),
                      DataCell(ProductsStatusBadge(isActive: product.isActive)),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'View product',
                              onPressed: () => onViewProduct(product),
                              icon: const Icon(
                                Icons.visibility_outlined,
                                size: 18,
                              ),
                            ),
                            IconButton(
                              tooltip: 'Edit product',
                              onPressed: () => onEditProduct(product),
                              icon: const Icon(Icons.edit_outlined, size: 18),
                            ),
                            PopupMenuButton<void>(
                              tooltip: 'More actions',
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  onTap: () => onToggleStatus(product),
                                  child: Row(
                                    children: [
                                      Icon(
                                        product.isActive
                                            ? Icons.block_outlined
                                            : Icons.check_circle_outline,
                                        size: 18,
                                      ),
                                      const SizedBox(width: AppSpacing.sm),
                                      Text(
                                        product.isActive
                                            ? 'Deactivate'
                                            : 'Reactivate',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          const Divider(height: 1),
          ProductsPagination(
            firstItem: firstItem,
            lastItem: lastItem,
            totalItems: totalItems,
            currentPage: currentPage,
            totalPages: totalPages,
            rowsPerPage: rowsPerPage,
            onPageChanged: onPageChanged,
            onRowsPerPageChanged: onRowsPerPageChanged,
          ),
        ],
      ),
    );
  }
}
