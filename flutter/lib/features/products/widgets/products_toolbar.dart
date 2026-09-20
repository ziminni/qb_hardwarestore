import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_shadows.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

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
    required this.onOpenSimulator,
  });

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
  final VoidCallback onOpenSimulator;

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
        boxShadow: const [AppShadows.card],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          final search = TextField(
            controller: _searchController,
            onChanged: widget.onSearchChanged,
            decoration: const InputDecoration(
              hintText: 'Search name, description, brand, or variant',
              prefixIcon: Icon(Icons.search),
            ),
          );
          final category = DropdownButtonFormField<String?>(
            initialValue: widget.selectedCategory,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('All categories'),
              ),
              ...widget.categories.map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              ),
            ],
            onChanged: widget.onCategoryChanged,
          );
          final brand = DropdownButtonFormField<String?>(
            initialValue: widget.selectedBrand,
            decoration: const InputDecoration(labelText: 'Brand'),
            items: [
              const DropdownMenuItem(value: null, child: Text('All brands')),
              ...widget.brands.map(
                (value) => DropdownMenuItem(value: value, child: Text(value)),
              ),
            ],
            onChanged: widget.onBrandChanged,
          );
          final heading = Row(
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
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  OutlinedButton.icon(
                    onPressed: widget.onOpenSimulator,
                    icon: const Icon(Icons.science_outlined, size: 18),
                    label: const Text('Inventory Simulator'),
                  ),
                  FilledButton.icon(
                    onPressed: widget.onAddProduct,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add product'),
                  ),
                ],
              ),
            ],
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                heading,
                const SizedBox(height: AppSpacing.lg),
                search,
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    SizedBox(width: 210, child: category),
                    SizedBox(width: 210, child: brand),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: widget.onClearFilters,
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
                    label: const Text('Clear filters'),
                  ),
                ),
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(flex: 3, child: search),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: category),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: brand),
                  const SizedBox(width: AppSpacing.md),
                ],
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
          );
        },
      ),
    );
  }
}
