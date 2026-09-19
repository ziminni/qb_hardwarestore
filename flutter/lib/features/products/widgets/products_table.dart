import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_shadows.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/products/widgets/products_empty_state.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:client/features/products/widgets/products_pagination.dart';
import 'package:flutter/material.dart';

enum ProductsLayoutView { grid, list, table, compact }

class ProductsTable extends StatefulWidget {
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
    required this.onArchiveProduct,
    required this.onClearFilters,
    required this.onPageChanged,
    required this.onRowsPerPageChanged,
    required this.onShowArchived,
    required this.archivedCount,
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
  final ValueChanged<Product> onArchiveProduct;
  final VoidCallback onClearFilters;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRowsPerPageChanged;
  final VoidCallback onShowArchived;
  final int archivedCount;

  @override
  State<ProductsTable> createState() => _ProductsTableState();
}

class _ProductsTableState extends State<ProductsTable> {
  ProductsLayoutView _layout = ProductsLayoutView.table;

  List<Product> get products => widget.products;
  Set<int> get selectedProductIds => widget.selectedProductIds;
  int get firstItem => widget.firstItem;
  int get lastItem => widget.lastItem;
  int get totalItems => widget.totalItems;
  int get currentPage => widget.currentPage;
  int get totalPages => widget.totalPages;
  int get rowsPerPage => widget.rowsPerPage;
  void Function(int, bool) get onSelectProduct => widget.onSelectProduct;
  ValueChanged<bool> get onSelectAll => widget.onSelectAll;
  ValueChanged<Product> get onViewProduct => widget.onViewProduct;
  ValueChanged<Product> get onEditProduct => widget.onEditProduct;
  ValueChanged<Product> get onArchiveProduct => widget.onArchiveProduct;
  VoidCallback get onClearFilters => widget.onClearFilters;
  ValueChanged<int> get onPageChanged => widget.onPageChanged;
  ValueChanged<int> get onRowsPerPageChanged => widget.onRowsPerPageChanged;
  VoidCallback get onShowArchived => widget.onShowArchived;
  int get archivedCount => widget.archivedCount;

  Widget _viewButton(
    BuildContext context,
    ProductsLayoutView view,
    IconData icon,
    String tooltip,
  ) {
    final selected = _layout == view;
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => setState(() => _layout = view),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 38,
          height: 34,
          decoration: BoxDecoration(
            color: selected ? colors.secondaryContainer : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Icon(
            icon,
            size: 19,
            color: selected ? colors.primary : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) => GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: products.length,
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 300,
            mainAxisExtent: 225,
            crossAxisSpacing: AppSpacing.md,
            mainAxisSpacing: AppSpacing.md,
          ),
          itemBuilder: (context, index) {
            final product = products[index];
            return Container(
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadii.medium),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => onViewProduct(product),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Checkbox(
                            value: selectedProductIds.contains(product.id),
                            onChanged: (value) =>
                                onSelectProduct(product.id, value ?? false),
                          ),
                          const Spacer(),
                          PopupMenuButton<String>(
                            tooltip: 'Product actions',
                            onSelected: (value) {
                              if (value == 'edit') onEditProduct(product);
                              if (value == 'archive') {
                                onArchiveProduct(product);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(
                                value: 'edit',
                                child: Text('Edit product'),
                              ),
                              PopupMenuItem(
                                value: 'archive',
                                child: Text('Move to archive'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Center(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.small),
                          child: ProductsImage(
                            imageUrl: product.imageUrl,
                            width: 72,
                            height: 72,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        product.baseName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${product.categoryName} · ${product.brandName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        '${product.variants.length} variant${product.variants.length == 1 ? '' : 's'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        children: [
          for (final product in products) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.xs,
              ),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    value: selectedProductIds.contains(product.id),
                    onChanged: (value) =>
                        onSelectProduct(product.id, value ?? false),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.small),
                    child: ProductsImage(
                      imageUrl: product.imageUrl,
                      width: 44,
                      height: 44,
                    ),
                  ),
                ],
              ),
              title: Text(
                product.baseName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '${product.categoryName} · ${product.brandName} · ${product.variants.length} variants',
              ),
              trailing: Wrap(
                spacing: AppSpacing.xs,
                children: [
                  IconButton(
                    tooltip: 'View product',
                    onPressed: () => onViewProduct(product),
                    icon: const Icon(Icons.visibility_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Edit product',
                    onPressed: () => onEditProduct(product),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Move to archive',
                    onPressed: () => onArchiveProduct(product),
                    icon: const Icon(Icons.archive_outlined, size: 18),
                  ),
                ],
              ),
              onTap: () => onViewProduct(product),
            ),
            if (product != products.last) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

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
        boxShadow: const [AppShadows.card],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            width: double.infinity,
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
                        'All products',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '$totalItems catalog ${totalItems == 1 ? 'entry' : 'entries'} found',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerLowest,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _viewButton(
                        context,
                        ProductsLayoutView.grid,
                        Icons.grid_view_outlined,
                        'Grid view',
                      ),
                      _viewButton(
                        context,
                        ProductsLayoutView.list,
                        Icons.format_list_bulleted,
                        'List view',
                      ),
                      _viewButton(
                        context,
                        ProductsLayoutView.table,
                        Icons.view_column_outlined,
                        'Table view',
                      ),
                      _viewButton(
                        context,
                        ProductsLayoutView.compact,
                        Icons.table_rows_outlined,
                        'Compact table',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                PopupMenuButton<String>(
                  tooltip: 'Product table options',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == 'archived') onShowArchived();
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'archived',
                      child: Row(
                        children: [
                          const Icon(Icons.archive_outlined, size: 18),
                          const SizedBox(width: AppSpacing.sm),
                          const Expanded(child: Text('Show archived')),
                          Text(
                            '$archivedCount',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (products.isEmpty)
            ProductsEmptyState(onClearFilters: onClearFilters)
          else if (_layout == ProductsLayoutView.grid)
            _buildGrid(context)
          else if (_layout == ProductsLayoutView.list)
            _buildList(context)
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                dataRowMinHeight: _layout == ProductsLayoutView.compact
                    ? 48
                    : 68,
                dataRowMaxHeight: _layout == ProductsLayoutView.compact
                    ? 48
                    : 68,
                headingRowHeight: 48,
                columnSpacing: AppSpacing.xl,
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
                                  width: _layout == ProductsLayoutView.compact
                                      ? 30
                                      : 46,
                                  height: _layout == ProductsLayoutView.compact
                                      ? 30
                                      : 46,
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
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: colors.secondaryContainer,
                            borderRadius: BorderRadius.circular(AppRadii.pill),
                          ),
                          child: Text(
                            product.categoryName,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ),
                      DataCell(Text(product.brandName)),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.layers_outlined,
                              size: 16,
                              color: colors.onSurfaceVariant,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text('${product.variants.length}'),
                          ],
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'View product',
                              onPressed: () => onViewProduct(product),
                              style: IconButton.styleFrom(
                                backgroundColor: colors.secondaryContainer,
                              ),
                              icon: const Icon(
                                Icons.visibility_outlined,
                                size: 17,
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
                                  onTap: () => onArchiveProduct(product),
                                  child: Row(
                                    children: [
                                      Icon(Icons.archive_outlined, size: 18),
                                      const SizedBox(width: AppSpacing.sm),
                                      Text('Move to archive'),
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
