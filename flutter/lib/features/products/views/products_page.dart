import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/widgets/async_view.dart';
import 'package:client/data/models/inventory.dart';
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

/// The products screen (Phase 4 Task 4).
///
/// Every action reaches the server: "Add product" posts the product, its first
/// variant and that variant's factor-1 selling unit; Edit and Archive/Restore
/// PATCH; and each one reloads. What used to happen instead was an in-memory
/// write behind a snackbar that admitted it — "Product added to mock inventory."
class ProductsPage extends StatefulWidget {
  const ProductsPage({super.key});

  @override
  State<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends State<ProductsPage> {
  @override
  void initState() {
    super.initState();
    // Fetch the catalogue once, when the screen opens (decision 12).
    //
    // Deferred to after the first frame on purpose: `load()` calls
    // notifyListeners() synchronously, and doing that from initState means
    // marking an element dirty while it is still being built. The view passes
    // `!hasLoaded` to AsyncView, so the spinner covers the first frame — the
    // store starts EMPTY now, and an empty state would claim "no products"
    // before anyone asked the server.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InventoryViewmodel>().load();
    });
  }

  void _announce(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showProductForm(
    BuildContext context,
    ProductsViewmodel viewModel, [
    Product? product,
  ]) async {
    final inventory = context.read<InventoryViewmodel>();
    final result = await showDialog<ProductFormResult>(
      context: context,
      builder: (_) => ProductsFormDialog(
        product: product,
        products: viewModel.products,
        categories: inventory.categories,
        brands: inventory.brands,
        units: inventory.units,
      ),
    );
    if (result == null) return;

    // Decision 11: the viewmodel delegates to the store, so each write is
    // applied ONCE, on the server, through one data path.
    final draft = result.draft;
    if (draft != null) {
      final error = await viewModel.createProduct(draft);
      _announce(error ?? '${draft.baseName} added to the catalogue.');
      return;
    }
    final edit = result.edit;
    if (edit == null) return;
    final error = await viewModel.editProduct(edit);
    _announce(error ?? '${edit.baseName ?? product?.baseName} updated.');
  }

  void _showProductDetails(BuildContext context, Product product) {
    showDialog<void>(
      context: context,
      builder: (_) => ProductsDetailsDialog(
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
      builder: (_) => ProductsArchivedDialog(
        products: viewModel.products
            .where((product) => !product.isActive)
            .toList(growable: false),
        onRestore: (product) => viewModel.setProductActive(product, true),
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
      builder: (dialogContext) => AlertDialog(
        title: const Text('Move product to archive?'),
        content: Text(
          '${product.baseName} will be removed from the product catalog and transaction selections. '
          'It is archived, never deleted, so it can be restored.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Move to archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final error = await viewModel.setProductActive(product, false);
    _announce(error ?? '${product.baseName} moved to archive.');
  }

  Future<void> _archiveSelected(
    BuildContext context,
    ProductsViewmodel viewModel,
  ) async {
    final selectedIds = viewModel.selectedProductIds;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Archive ${selectedIds.length} products?'),
        content: const Text(
          'The selected products will no longer appear in the main product catalog.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.archive_outlined),
            label: const Text('Move to archive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final error = await viewModel.archiveSelectedProducts();
    _announce(error ?? '${selectedIds.length} products moved to archive.');
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) =>
          ProductsViewmodel(context.read<InventoryViewmodel>()),
      child: Consumer<ProductsViewmodel>(
        builder: (context, viewModel, child) {
          final inventory = context.watch<InventoryViewmodel>();
          return InventorySkeletonLayout(
            title: 'Products',
            subtitle: 'View and organize the hardware product catalog.',
            selectedNavigationIndex: 1,
            onNavigationSelected: (index) => navigateInventory(context, index),
            // Decision 07: one shared widget owns loading, error, empty and data,
            // with the precedence baked in so the builder only runs with data.
            // `!hasLoaded` keeps the spinner up for the frame before the first
            // load attempt, when the store is still empty rather than mock.
            child: AsyncView(
              isLoading: inventory.isLoading || !inventory.hasLoaded,
              error: inventory.loadError,
              isEmpty: inventory.products.isEmpty,
              emptyMessage: 'No products in the catalogue yet.',
              onRetry: inventory.load,
              builder: (context) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ProductsCatalogOverview(
                    totalProducts: viewModel.totalProducts,
                    totalVariants: viewModel.totalVariants,
                    archivedProducts: viewModel.archivedProducts,
                    categoryCount: viewModel.categories.length,
                    brandCount: viewModel.brands.length,
                    lowStockVariants: inventory.stockRecords
                        .where(
                          (record) =>
                              inventory.statusForVariant(record.variant.id) ==
                              InventoryStockStatus.lowStock,
                        )
                        .length,
                    outOfStockVariants: inventory.stockRecords
                        .where(
                          (record) =>
                              inventory.statusForVariant(record.variant.id) ==
                              InventoryStockStatus.outOfStock,
                        )
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
            ),
          );
        },
      ),
    );
  }
}
