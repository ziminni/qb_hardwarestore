import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/storage_location.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'dart:math';

import 'package:flutter/material.dart';

/// Search plus the category, brand and stock location filters, at the head of
/// the catalogue.
///
/// The search field is the shared [FilterBar]; the dropdowns share a row while
/// they fit and wrap under each other when they do not, so no filter is ever
/// given a fixed slot in a `Row` that can overflow (the live report this
/// replaces: "A RenderFlex overflowed by 13 pixels on the right").
class ProductsToolbar extends StatefulWidget {
  const ProductsToolbar({
    super.key,
    required this.searchQuery,
    required this.categories,
    required this.brands,
    required this.selectedCategory,
    required this.selectedBrand,
    required this.stockLocations,
    required this.selectedStockLocationId,
    required this.onSearchChanged,
    required this.onCategoryChanged,
    required this.onBrandChanged,
    required this.onStockLocationChanged,
    required this.onClearFilters,
    required this.onAddProduct,
  });

  /// Width of the toolbar's own content below which the filters drop under the
  /// search field. Above it, search and all three dropdowns share one row: the
  /// search takes what is left, so the row can never overflow.
  static const double sideBySideAbove = 1120;

  /// Enough for "All categories" plus a chevron and a long server-side name.
  static const double filterWidth = 240;

  final String searchQuery;
  final List<String> categories;
  final List<String> brands;
  final String? selectedCategory;
  final String? selectedBrand;
  final List<StorageLocation> stockLocations;
  final int? selectedStockLocationId;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onBrandChanged;
  final ValueChanged<int?> onStockLocationChanged;
  final VoidCallback onClearFilters;
  final VoidCallback onAddProduct;

  @override
  State<ProductsToolbar> createState() => _ProductsToolbarState();
}

class _ProductsToolbarState extends State<ProductsToolbar> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchQuery);
  }

  @override
  void didUpdateWidget(covariant ProductsToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The page owns the query (a cleared filter or a fresh load rewrites it), so
    // the field follows the value it is handed instead of keeping its own.
    if (widget.searchQuery != _searchController.text) {
      _searchController.value = TextEditingValue(
        text: widget.searchQuery,
        selection: TextSelection.collapsed(offset: widget.searchQuery.length),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Widget _categoryField() {
    return DropdownButtonFormField<String?>(
      isExpanded: true,
      initialValue: widget.selectedCategory,
      decoration: const InputDecoration(labelText: 'Category'),
      items: [
        const DropdownMenuItem(value: null, child: Text('All categories')),
        ...widget.categories.map(
          (value) => DropdownMenuItem(
            value: value,
            child: Text(value, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: widget.onCategoryChanged,
    );
  }

  Widget _brandField() {
    return DropdownButtonFormField<String?>(
      isExpanded: true,
      initialValue: widget.selectedBrand,
      decoration: const InputDecoration(labelText: 'Brand'),
      items: [
        const DropdownMenuItem(value: null, child: Text('All brands')),
        ...widget.brands.map(
          (value) => DropdownMenuItem(
            value: value,
            child: Text(value, overflow: TextOverflow.ellipsis),
          ),
        ),
      ],
      onChanged: widget.onBrandChanged,
    );
  }

  /// The stock location filter (Task 19), by the SERVER's location id.
  ///
  /// The key is the chosen id so a programmatic reset (Clear filters) redraws the
  /// field: `DropdownButtonFormField` only reads `initialValue` once per state.
  Widget _stockLocationField() {
    return DropdownButtonFormField<int?>(
      key: ValueKey<int?>(widget.selectedStockLocationId),
      isExpanded: true,
      initialValue: widget.selectedStockLocationId,
      decoration: const InputDecoration(labelText: 'Stock location'),
      items: [
        const DropdownMenuItem(value: null, child: Text('All locations')),
        ...widget.stockLocations.map(
          (location) => DropdownMenuItem(
            value: location.id,
            // A deactivated shelf still holds sellable stock, so it is offered
            // and its state is said out loud rather than hidden.
            child: Text(
              location.isActive ? location.name : '${location.name} (inactive)',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
      onChanged: widget.onStockLocationChanged,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Product catalog',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Search the catalog or narrow results using filters.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                onPressed: widget.onAddProduct,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add product'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final search = FilterBar(
                searchController: _searchController,
                searchHint: 'Search name, description, brand, or variant',
                onSearchChanged: widget.onSearchChanged,
              );
              final filters = [
                _categoryField(),
                _brandField(),
                _stockLocationField(),
              ];
              if (constraints.maxWidth >= ProductsToolbar.sideBySideAbove) {
                return Row(
                  children: [
                    Expanded(child: search),
                    for (final filter in filters) ...[
                      const SizedBox(width: AppSpacing.md),
                      SizedBox(
                        width: ProductsToolbar.filterWidth,
                        child: filter,
                      ),
                    ],
                  ],
                );
              }
              // Narrow: the search keeps a full line of its own, then the
              // filters take as many lines as they need — never a fixed-width
              // slot in a Row that can overflow.
              final filterWidth = min(
                ProductsToolbar.filterWidth,
                constraints.maxWidth,
              );
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  search,
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final filter in filters)
                        SizedBox(width: filterWidth, child: filter),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
          // Say what the filter means: it narrows by WHERE stock is, and the
          // quantities on screen stay totals, so nobody reads them as this
          // shelf's count.
          const Text(
            'Shows products with stock available at the chosen location. '
            'Quantities shown are still totals across every location.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onClearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
              label: const Text('Clear filters'),
            ),
          ),
        ],
      ),
    );
  }
}
