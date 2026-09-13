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
    required this.activeStatus,
    required this.onSearchChanged,
    required this.onCategoryChanged,
    required this.onBrandChanged,
    required this.onStatusChanged,
    required this.onClearFilters,
    required this.onAddProduct,
  });

  final String searchQuery;
  final List<String> categories;
  final List<String> brands;
  final String? selectedCategory;
  final String? selectedBrand;
  final bool? activeStatus;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<String?> onBrandChanged;
  final ValueChanged<bool?> onStatusChanged;
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
    return LayoutBuilder(
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
            const DropdownMenuItem(value: null, child: Text('All categories')),
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
        final status = DropdownButtonFormField<bool?>(
          initialValue: widget.activeStatus,
          decoration: const InputDecoration(labelText: 'Status'),
          items: const [
            DropdownMenuItem(value: null, child: Text('All statuses')),
            DropdownMenuItem(value: true, child: Text('Active')),
            DropdownMenuItem(value: false, child: Text('Inactive')),
          ],
          onChanged: widget.onStatusChanged,
        );
        final actions = Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: widget.onClearFilters,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Clear'),
            ),
            FilledButton.icon(
              onPressed: widget.onAddProduct,
              icon: const Icon(Icons.add),
              label: const Text('Add product'),
            ),
          ],
        );

        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.md,
                children: [
                  SizedBox(width: 210, child: category),
                  SizedBox(width: 210, child: brand),
                  SizedBox(width: 180, child: status),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Align(alignment: Alignment.centerRight, child: actions),
            ],
          );
        }

        return Column(
          children: [
            Row(
              children: [
                Expanded(flex: 3, child: search),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: category),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: brand),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: status),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Align(alignment: Alignment.centerRight, child: actions),
          ],
        );
      },
    );
  }
}
