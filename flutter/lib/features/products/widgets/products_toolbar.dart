import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';

/// Search plus the category and brand filters, at the head of the catalogue.
///
/// The search field is the shared [FilterBar] and the two dropdowns sit in a
/// row that becomes a stack when the toolbar itself gets narrow, so no filter is
/// ever given a fixed 210 px slot in a `Row` that can overflow (the live report
/// this replaces: "A RenderFlex overflowed by 13 pixels on the right").
class ProductsToolbar extends StatefulWidget {
  const ProductsToolbar({
    super.key,
    required this.searchQuery,
    required this.categories,
    required this.brands,
    required this.selectedCategory,
    required this.selectedBrand,
    required this.onSearchChanged,
    required this.onCategoryChanged,
    required this.onBrandChanged,
    required this.onClearFilters,
    required this.onAddProduct,
  });

  /// Width of the toolbar's own content below which the filters drop under the
  /// search field. Above it, search and both dropdowns share one row: the search
  /// takes what is left, so the row can never overflow.
  static const double sideBySideAbove = 820;

  /// Enough for "All categories" plus a chevron and a long server-side name.
  static const double filterWidth = 240;

  /// Below [sideBySideAbove] the search keeps a line of its own; these two
  /// filters still fit on one line until the toolbar's content is this narrow.
  static const double twoFiltersAbove = 520;

  final String searchQuery;
  final List<String> categories;
  final List<String> brands;
  final String? selectedCategory;
  final String? selectedBrand;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onBrandChanged;
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
              if (constraints.maxWidth >= ProductsToolbar.sideBySideAbove) {
                return Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: AppSpacing.md),
                    SizedBox(
                      width: ProductsToolbar.filterWidth,
                      child: _categoryField(),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    SizedBox(
                      width: ProductsToolbar.filterWidth,
                      child: _brandField(),
                    ),
                  ],
                );
              }
              // Narrow: the search keeps a full line of its own, then the two
              // filters share one line while they still fit side by side and
              // stack under each other when they do not.
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  search,
                  const SizedBox(height: AppSpacing.md),
                  if (constraints.maxWidth >= ProductsToolbar.twoFiltersAbove)
                    Row(
                      children: [
                        Expanded(child: _categoryField()),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: _brandField()),
                      ],
                    )
                  else ...[
                    _categoryField(),
                    const SizedBox(height: AppSpacing.md),
                    _brandField(),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.sm),
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
