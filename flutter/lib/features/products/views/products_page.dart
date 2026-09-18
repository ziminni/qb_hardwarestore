import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/products/viewmodels/products_viewmodel.dart';
import 'package:client/features/products/widgets/products_bulk_actions.dart';
import 'package:client/features/products/widgets/products_details_dialog.dart';
import 'package:client/features/products/widgets/products_form_dialog.dart';
import 'package:client/features/products/widgets/products_summary_card.dart';
import 'package:client/features/products/widgets/products_table.dart';
import 'package:client/features/products/widgets/products_toolbar.dart';
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
                LayoutBuilder(
                  builder: (context, constraints) {
                    final columns = constraints.maxWidth >= 1060
                        ? 4
                        : constraints.maxWidth >= 540
                        ? 2
                        : 1;
                    final cardWidth =
                        (constraints.maxWidth -
                            (AppSpacing.md * (columns - 1))) /
                        columns;

                    return Wrap(
                      spacing: AppSpacing.md,
                      runSpacing: AppSpacing.md,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          child: ProductsSummaryCard(
                            label: 'Total products',
                            value: '${viewModel.totalProducts}',
                            icon: Icons.inventory_2_outlined,
                            caption: 'Catalog entries',
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: ProductsSummaryCard(
                            label: 'Active',
                            value: '${viewModel.activeProducts}',
                            icon: Icons.check_circle_outline,
                            caption: 'Available for transactions',
                            color: AppColors.success,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: ProductsSummaryCard(
                            label: 'Inactive',
                            value: '${viewModel.inactiveProducts}',
                            icon: Icons.block_outlined,
                            caption: 'Hidden from transactions',
                            color: AppColors.error,
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          child: ProductsSummaryCard(
                            label: 'Variants',
                            value: '${viewModel.totalVariants}',
                            icon: Icons.format_list_bulleted_outlined,
                            caption: 'Sizes and specifications',
                            color: AppColors.info,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.xl),
                ProductsToolbar(
                  searchQuery: viewModel.searchQuery,
                  categories: viewModel.categories,
                  brands: viewModel.brands,
                  selectedCategory: viewModel.selectedCategory,
                  selectedBrand: viewModel.selectedBrand,
                  activeStatus: viewModel.activeStatus,
                  onSearchChanged: viewModel.setSearchQuery,
                  onCategoryChanged: viewModel.setCategory,
                  onBrandChanged: viewModel.setBrand,
                  onStatusChanged: viewModel.setActiveStatus,
                  onClearFilters: viewModel.clearFilters,
                  onAddProduct: () => _showProductForm(context, viewModel),
                ),
                if (viewModel.selectedProductIds.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  ProductsBulkActions(
                    selectedCount: viewModel.selectedProductIds.length,
                    onActivate: () => viewModel.setSelectedProductsActive(true),
                    onDeactivate: () =>
                        viewModel.setSelectedProductsActive(false),
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
                  onToggleStatus: viewModel.toggleProductStatus,
                  onClearFilters: viewModel.clearFilters,
                  onPageChanged: viewModel.goToPage,
                  onRowsPerPageChanged: viewModel.setRowsPerPage,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
