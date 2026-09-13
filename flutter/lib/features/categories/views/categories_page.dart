import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/category.dart';
import 'package:client/features/categories/widgets/inventory_categories_table.dart';
import 'package:client/features/categories/widgets/inventory_category_dialog.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  String _query = '';

  Future<void> _open(Category category, bool editing) async {
    final inventory = context.read<InventoryViewmodel>();
    final result = await showDialog<Category>(
      context: context,
      builder: (_) => InventoryCategoryDialog(
        category: category,
        products: inventory.productsForCategory(category.id),
        editing: editing,
      ),
    );
    if (result != null) {
      inventory.updateCategory(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Category updated in mock data.')),
        );
      }
    }
  }

  Future<void> _archive(Category category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Archive category?'),
        content: Text('${category.name} will remain visible as archived.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      context.read<InventoryViewmodel>().archiveCategory(category);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    final categories = inventory.categories
        .where(
          (item) =>
              item.name.toLowerCase().contains(_query.toLowerCase()) ||
              item.description.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();
    return InventorySkeletonLayout(
      title: 'Categories',
      subtitle: 'Organize related construction products.',
      selectedNavigationIndex: 2,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 360,
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search categories',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          InventoryCategoriesTable(
            categories: categories,
            productCount: inventory.productCountForCategory,
            onView: (item) => _open(item, false),
            onEdit: (item) => _open(item, true),
            onArchive: _archive,
          ),
        ],
      ),
    );
  }
}
