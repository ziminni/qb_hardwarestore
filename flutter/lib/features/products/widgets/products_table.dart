import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:client/features/products/widgets/products_pagination.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// The four ways to look at the catalogue. All four are kept on purpose (D8):
/// each one answers a different question, and removing one is the user's call.
enum ProductsLayoutView { grid, list, table, compact }

/// The catalogue itself: a heading with the view switcher, then the rows in the
/// chosen layout, then the pager.
///
/// The table view is the shared [DataPanel], so at 1440 px it fills the panel
/// and under 720 px of panel width the same rows become cards: a table that
/// scrolls sideways hides the price and the row menu off the right edge, which
/// is exactly what the old raw `DataTable` did at 760 px.
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
    required this.onPrintLabels,
    required this.onClearFilters,
    required this.onPageChanged,
    required this.onRowsPerPageChanged,
    required this.onShowArchived,
    required this.archivedCount,
    required this.stockStatusFor,
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

  /// Opens the label picker for this product's selling units (decision 14).
  final ValueChanged<Product> onPrintLabels;
  final VoidCallback onClearFilters;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onRowsPerPageChanged;
  final VoidCallback onShowArchived;
  final int archivedCount;

  /// Stock state of the product's first variant, read from the store the page
  /// already loaded. Null when the product has no variant to count yet.
  final InventoryStockStatus? Function(Product product) stockStatusFor;

  @override
  State<ProductsTable> createState() => _ProductsTableState();
}

class _ProductsTableState extends State<ProductsTable> {
  ProductsLayoutView _layout = ProductsLayoutView.table;

  List<Product> get products => widget.products;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _header(context),
        const SizedBox(height: AppSpacing.md),
        if (products.isEmpty)
          AppPanel(
            child: EmptyState(
              icon: Icons.inventory_2_outlined,
              message: 'No products found',
              actionLabel: 'Clear filters',
              onAction: widget.onClearFilters,
            ),
          )
        else
          switch (_layout) {
            ProductsLayoutView.table => _table(),
            ProductsLayoutView.grid => AppPanel(child: _grid()),
            ProductsLayoutView.list => AppPanel(child: _list(context)),
            ProductsLayoutView.compact => AppPanel(child: _compact(context)),
          },
        const SizedBox(height: AppSpacing.md),
        ProductsPagination(
          firstItem: widget.firstItem,
          lastItem: widget.lastItem,
          totalItems: widget.totalItems,
          currentPage: widget.currentPage,
          totalPages: widget.totalPages,
          rowsPerPage: widget.rowsPerPage,
          onPageChanged: widget.onPageChanged,
          onRowsPerPageChanged: widget.onRowsPerPageChanged,
        ),
      ],
    );
  }

  // ------------------------------------------------------------- heading

  /// The catalogue heading, the select-all control, the view switcher and the
  /// archived list. A `Wrap`, so the controls drop to their own line instead of
  /// pushing the heading off the panel on a narrow window.
  Widget _header(BuildContext context) {
    final allVisibleSelected =
        products.isNotEmpty &&
        products.every(
          (product) => widget.selectedProductIds.contains(product.id),
        );

    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.sm,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'All products',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.totalItems} catalog '
              '${widget.totalItems == 1 ? 'entry' : 'entries'} found',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: 'Select all products',
              child: Checkbox(
                key: const ValueKey('ProductsSelectAll'),
                value: allVisibleSelected,
                onChanged: (value) => widget.onSelectAll(value ?? false),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            Container(
              padding: const EdgeInsets.all(AppSpacing.xs),
              decoration: BoxDecoration(
                color: AppColors.background,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _viewButton(
                    ProductsLayoutView.grid,
                    Icons.grid_view_outlined,
                    'Grid view',
                  ),
                  _viewButton(
                    ProductsLayoutView.list,
                    Icons.format_list_bulleted,
                    'List view',
                  ),
                  _viewButton(
                    ProductsLayoutView.table,
                    Icons.view_column_outlined,
                    'Table view',
                  ),
                  _viewButton(
                    ProductsLayoutView.compact,
                    Icons.table_rows_outlined,
                    'Compact table',
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Product table options',
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'archived') widget.onShowArchived();
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
                        '${widget.archivedCount}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _viewButton(ProductsLayoutView view, IconData icon, String tooltip) {
    final selected = _layout == view;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () => setState(() => _layout = view),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: 44,
          height: 36,
          decoration: BoxDecoration(
            color: selected ? AppColors.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Icon(
            icon,
            size: 19,
            color: selected ? AppColors.brandGoldText : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- table

  Widget _table() {
    return DataPanel<Product>(
      columns: [
        // The name is what this table is scanned for, so it takes three shares
        // and stops ellipsizing while Variants holds a single digit. Price takes
        // two so a seven figure amount keeps its centavos. At a 1.3x text scale
        // Variants and Price each take one share more: a header one word long
        // ("Variants") and a centavo-accurate amount both outgrew one line of
        // their column, and the header was cut to "Varia...".
        DataPanelColumn<Product>(label: 'Product', flex: 3, cell: _productCell),
        DataPanelColumn<Product>(
          label: 'Variants',
          numeric: true,
          flex: 2,
          cell: (product) => Text(
            formatCount(product.variants.length),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        DataPanelColumn<Product>(
          label: 'Price',
          numeric: true,
          flex: 3,
          cell: (product) => Text(
            _price(product),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Two shares, like the rest: one share cut the "Out of Stock" badge
        // onto two lines once Variants and Price took the room they need.
        DataPanelColumn<Product>(label: 'Stock', flex: 2, cell: _stockBadge),
        // Three icon buttons at the 44 px touch target do not fit one share: two
        // shares keep them inside the row instead of overflowing it.
        DataPanelColumn<Product>(label: 'Actions', flex: 2, cell: _actionsCell),
      ],
      rows: products,
      emptyMessage: 'No products found',
      onRowTap: widget.onViewProduct,
      rowKey: (product) => ValueKey('ProductsRow.${product.id}'),
    );
  }

  Widget _productCell(Product product) {
    // Category and brand travel with the name, the way the till's product card
    // shows them: as columns of their own they took a third of the width from
    // the name a stock manager actually reads.
    final caption = [
      product.categoryName,
      product.brandName,
    ].where((part) => part.isNotEmpty).join(' · ');

    return Row(
      children: [
        Checkbox(
          key: ValueKey('ProductsRowSelect.${product.id}'),
          value: widget.selectedProductIds.contains(product.id),
          onChanged: (value) =>
              widget.onSelectProduct(product.id, value ?? false),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          semanticLabel: 'Select ${product.baseName}',
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.baseName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
              ),
              if (caption.isNotEmpty)
                Text(
                  caption.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  /// The BASE unit's price, with that unit named (Phase 1d Task 9).
  ///
  /// Price belongs to a selling unit (decision 08). The first row is not the
  /// base: once a product is sold by the bag the server may answer
  /// `[BAG (×40), KG (×1)]`, and the old caption made the bag's money look like
  /// the price of one kilogram. A product with no identifiable base row falls
  /// back to its first unit, whose own code still keeps the caption honest.
  String _price(Product product) {
    for (final variant in product.variants) {
      final unit = variant.baseSellingUnit ?? variant.sellingUoms.firstOrNull;
      if (unit == null) continue;
      return '${formatPeso(unit.defaultSellingPrice)} / ${unit.uomCode}';
    }
    return 'No price yet';
  }

  /// The stock state as a pill. Words plus color, because a color alone is
  /// unreadable for a color blind stock manager.
  Widget _stockBadge(Product product) {
    final status = widget.stockStatusFor(product);
    if (status == null) {
      return const StatusBadge(label: 'Not counted yet');
    }
    return StatusBadge(
      label: status.label,
      tone: switch (status) {
        InventoryStockStatus.inStock => StatusTone.success,
        InventoryStockStatus.lowStock => StatusTone.warning,
        InventoryStockStatus.outOfStock => StatusTone.error,
      },
    );
  }

  Widget _actionsCell(Product product) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'View product',
          onPressed: () => widget.onViewProduct(product),
          icon: const Icon(Icons.visibility_outlined, size: 18),
        ),
        IconButton(
          tooltip: 'Edit product',
          onPressed: () => widget.onEditProduct(product),
          icon: const Icon(Icons.edit_outlined, size: 18),
        ),
        PopupMenuButton<String>(
          tooltip: 'More actions',
          icon: const Icon(Icons.more_vert, size: 18),
          onSelected: (value) {
            if (value == 'labels') widget.onPrintLabels(product);
            if (value == 'archive') widget.onArchiveProduct(product);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'labels', child: Text('Print labels')),
            PopupMenuItem(value: 'archive', child: Text('Move to archive')),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------- grid

  /// Cards that size themselves: the column count follows the panel width and
  /// each card is as tall as its own content, never a fixed 225 px that clips a
  /// long name in another font.
  Widget _grid() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth;
        final columns = available >= 900
            ? 3
            : available >= 600
            ? 2
            : 1;
        final cardWidth = (available - AppSpacing.md * (columns - 1)) / columns;
        return Wrap(
          key: const ValueKey('ProductsGrid'),
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final product in products)
              SizedBox(width: cardWidth, child: _card(context, product)),
          ],
        );
      },
    );
  }

  Widget _card(BuildContext context, Product product) {
    final caption = [
      product.categoryName,
      product.brandName,
    ].where((part) => part.isNotEmpty).join(' · ');
    return Material(
      color: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => widget.onViewProduct(product),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Checkbox(
                    key: ValueKey('ProductsRowSelect.${product.id}'),
                    value: widget.selectedProductIds.contains(product.id),
                    onChanged: (value) =>
                        widget.onSelectProduct(product.id, value ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    semanticLabel: 'Select ${product.baseName}',
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    tooltip: 'Product actions',
                    onSelected: (value) {
                      if (value == 'edit') widget.onEditProduct(product);
                      if (value == 'labels') widget.onPrintLabels(product);
                      if (value == 'archive') {
                        widget.onArchiveProduct(product);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit product')),
                      PopupMenuItem(
                        value: 'labels',
                        child: Text('Print labels'),
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
              const SizedBox(height: AppSpacing.sm),
              if (caption.isNotEmpty) ...[
                Text(
                  caption.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
              ],
              Text(
                product.baseName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${formatCount(product.variants.length)} '
                '${product.variants.length == 1 ? 'variant' : 'variants'}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    _price(product),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                      color: AppColors.textPrimary,
                    ),
                  ),
                  _stockBadge(product),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- list

  Widget _list(BuildContext context) {
    // The panel paints its own background, so a ListTile inside it needs a
    // Material of its own or its ink splash is painted behind that background.
    return Material(
      type: MaterialType.transparency,
      child: Column(
        key: const ValueKey('ProductsList'),
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final product in products) ...[
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Checkbox(
                    key: ValueKey('ProductsRowSelect.${product.id}'),
                    value: widget.selectedProductIds.contains(product.id),
                    onChanged: (value) =>
                        widget.onSelectProduct(product.id, value ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    semanticLabel: 'Select ${product.baseName}',
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                '${product.categoryName} · ${product.brandName} · '
                '${formatCount(product.variants.length)} '
                '${product.variants.length == 1 ? 'variant' : 'variants'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _price(product),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  PopupMenuButton<String>(
                    tooltip: 'More actions',
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: (value) {
                      if (value == 'edit') widget.onEditProduct(product);
                      if (value == 'labels') widget.onPrintLabels(product);
                      if (value == 'archive') widget.onArchiveProduct(product);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit product')),
                      PopupMenuItem(
                        value: 'labels',
                        child: Text('Print labels'),
                      ),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text('Move to archive'),
                      ),
                    ],
                  ),
                ],
              ),
              onTap: () => widget.onViewProduct(product),
            ),
            if (product != products.last) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------- compact

  /// The dense variant: everything on one line, for a stock manager scanning
  /// many rows. Kept alongside the table (D8) because it fits twice as many
  /// records on a laptop screen.
  Widget _compact(BuildContext context) {
    final allVisibleSelected = products.every(
      (product) => widget.selectedProductIds.contains(product.id),
    );

    return SingleChildScrollView(
      key: const ValueKey('ProductsCompactTable'),
      scrollDirection: Axis.horizontal,
      child: DataTable(
        dataRowMinHeight: 48,
        dataRowMaxHeight: 48,
        headingRowHeight: 48,
        columnSpacing: AppSpacing.xl,
        headingRowColor: const WidgetStatePropertyAll(AppColors.background),
        columns: [
          DataColumn(
            label: Checkbox(
              value: allVisibleSelected,
              onChanged: (value) => widget.onSelectAll(value ?? false),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const DataColumn(label: Text('Product')),
          const DataColumn(label: Text('Category')),
          const DataColumn(label: Text('Brand')),
          const DataColumn(label: Text('Variants')),
          const DataColumn(label: Text('Price')),
          const DataColumn(label: Text('Stock')),
          const DataColumn(label: Text('Actions')),
        ],
        rows: [
          for (final product in products)
            DataRow(
              selected: widget.selectedProductIds.contains(product.id),
              cells: [
                DataCell(
                  Checkbox(
                    key: ValueKey('ProductsRowSelect.${product.id}'),
                    value: widget.selectedProductIds.contains(product.id),
                    onChanged: (value) =>
                        widget.onSelectProduct(product.id, value ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 220,
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadii.small),
                          child: ProductsImage(
                            imageUrl: product.imageUrl,
                            width: 30,
                            height: 30,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            product.baseName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                DataCell(
                  Text(
                    product.categoryName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(
                  Text(
                    product.brandName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(Text(formatCount(product.variants.length))),
                DataCell(Text(_price(product))),
                DataCell(_stockBadge(product)),
                DataCell(_actionsCell(product)),
              ],
            ),
        ],
      ),
    );
  }
}
