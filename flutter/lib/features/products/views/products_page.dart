import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/products/viewmodels/products_viewmodel.dart';
import 'package:client/features/products/widgets/products_bulk_actions.dart';
import 'package:client/features/products/widgets/products_archived_dialog.dart';
import 'package:client/features/products/widgets/products_details_dialog.dart';
import 'package:client/features/products/widgets/products_form_dialog.dart';
import 'package:client/features/products/widgets/products_catalog_overview.dart';
import 'package:client/features/products/widgets/products_table.dart';
import 'package:client/features/products/widgets/products_toolbar.dart';
import 'package:client/features/products/widgets/products_inventory_simulator_dialog.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ProductsPage extends StatelessWidget {
  const ProductsPage({super.key});

  Future<void> _showProductForm(
    BuildContext context,
    ProductsViewmodel viewModel, [
    Product? product,
  ]) async {
    final categories = <int, Product>{
      for (final item in viewModel.products) item.categoryId: item,
    }.values.toList();
    final brands = <int, Product>{
      for (final item in viewModel.products) item.brandId: item,
    }.values.toList();

    final result = await showDialog<Product>(
      context: context,
      builder: (context) => ProductsFormDialog(
        product: product,
        categories: categories,
        brands: brands,
      ),
    );
    if (result == null || !context.mounted) return;

    final inventory = context.read<InventoryViewmodel>();
    if (product == null) {
      viewModel.addProduct(result);
      inventory.addProduct(result);
    } else {
      viewModel.updateProduct(result);
      inventory.updateProduct(result);
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            product == null
                ? 'Product added to mock inventory.'
                : 'Product updated in mock inventory.',
          ),
        ),
      );
    }
  }

  void _showProductDetails(BuildContext context, Product product) {
    showDialog<void>(
      context: context,
      builder: (context) => ProductsDetailsDialog(
        product: product,
        movements: context
            .read<InventoryViewmodel>()
            .movements
            .where((item) => item.productId == product.id)
            .toList(),
        tracking: context.read<ProductTrackingViewmodel>().configurationFor(
          product.baseName,
        ),
      ),
    );
  }

  void _showArchivedProducts(
    BuildContext context,
    ProductsViewmodel viewModel,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => ProductsArchivedDialog(
        products: viewModel.products
            .where((product) => !product.isActive)
            .toList(growable: false),
      ),
    );
  }

  Future<void> _archiveProduct(
    BuildContext context,
    ProductsViewmodel viewModel,
    Product product,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Move product to archive?'),
        content: Text(
          '${product.baseName} will be removed from the product catalog and transaction selections.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Move to archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final archived = product.copyWith(isActive: false);
    viewModel.archiveProduct(product);
    context.read<InventoryViewmodel>().updateProduct(archived);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${product.baseName} moved to archive.')),
    );
  }

  Future<void> _archiveSelected(
    BuildContext context,
    ProductsViewmodel viewModel,
  ) async {
    final selectedIds = viewModel.selectedProductIds;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Archive ${selectedIds.length} products?'),
        content: const Text(
          'The selected products will no longer appear in the main product catalog.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Move to archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final inventory = context.read<InventoryViewmodel>();
    for (final product in viewModel.products) {
      if (selectedIds.contains(product.id)) {
        inventory.updateProduct(product.copyWith(isActive: false));
      }
    }
    viewModel.archiveSelectedProducts();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${selectedIds.length} products moved to archive.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          ProductsViewmodel(context.read<InventoryViewmodel>().products),
      child: Consumer<ProductsViewmodel>(
        builder: (context, viewModel, child) {
          return InventorySkeletonLayout(
            title: 'Products',
            subtitle: 'View and organize the hardware product catalog.',
            selectedNavigationIndex: 1,
            onNavigationSelected: (index) => navigateInventory(context, index),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProductsCatalogOverview(
                  totalProducts: viewModel.totalProducts,
                  totalVariants: viewModel.totalVariants,
                  archivedProducts: viewModel.archivedProducts,
                  categoryCount: viewModel.categories.length,
                  brandCount: viewModel.brands.length,
                  lowStockVariants: context
                      .watch<InventoryViewmodel>()
                      .stockRecords
                      .where(
                        (record) =>
                            record.variant.currentStock > 0 &&
                            record.variant.currentStock <=
                                record.variant.reorderLevel,
                      )
                      .length,
                  outOfStockVariants: context
                      .watch<InventoryViewmodel>()
                      .stockRecords
                      .where((record) => record.variant.currentStock <= 0)
                      .length,
                  onShowAll: viewModel.clearFilters,
                  onShowLowStock: () => navigateInventory(context, 5),
                ),
                const SizedBox(height: AppSpacing.xl),
                ProductsToolbar(
                  searchQuery: viewModel.searchQuery,
                  categories: viewModel.categories,
                  brands: viewModel.brands,
                  selectedCategory: viewModel.selectedCategory,
                  selectedBrand: viewModel.selectedBrand,
                  onSearchChanged: viewModel.setSearchQuery,
                  onCategoryChanged: viewModel.setCategory,
                  onBrandChanged: viewModel.setBrand,
                  onClearFilters: viewModel.clearFilters,
                  onAddProduct: () => _showProductForm(context, viewModel),
                  onOpenSimulator: () => showDialog<void>(
                    context: context,
                    builder: (_) => const ProductsInventorySimulatorDialog(),
                  ),
                ),
                if (viewModel.selectedProductIds.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  ProductsBulkActions(
                    selectedCount: viewModel.selectedProductIds.length,
                    onArchive: () => _archiveSelected(context, viewModel),
                    onClear: viewModel.clearSelection,
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                ProductsTable(
                  products: viewModel.visibleProducts,
                  selectedProductIds: viewModel.selectedProductIds,
                  firstItem: viewModel.firstVisibleItem,
                  lastItem: viewModel.lastVisibleItem,
                  totalItems: viewModel.filteredProducts.length,
                  currentPage: viewModel.currentPage,
                  totalPages: viewModel.totalPages,
                  rowsPerPage: viewModel.rowsPerPage,
                  onSelectProduct: viewModel.toggleSelection,
                  onSelectAll: viewModel.selectVisibleProducts,
                  onViewProduct: (product) =>
                      _showProductDetails(context, product),
                  onEditProduct: (product) =>
                      _showProductForm(context, viewModel, product),
                  onArchiveProduct: (product) =>
                      _archiveProduct(context, viewModel, product),
                  onClearFilters: viewModel.clearFilters,
                  onPageChanged: viewModel.goToPage,
                  onRowsPerPageChanged: viewModel.setRowsPerPage,
                  archivedCount: viewModel.archivedProducts,
                  onShowArchived: () =>
                      _showArchivedProducts(context, viewModel),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
