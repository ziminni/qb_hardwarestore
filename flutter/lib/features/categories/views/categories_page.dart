import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/category.dart';
import 'package:client/features/categories/widgets/inventory_category_card.dart';
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
    final activeCount = inventory.categories
        .where((item) => item.isActive)
        .length;
    final archivedCount = inventory.categories.length - activeCount;
    return InventorySkeletonLayout(
      title: 'Categories',
      subtitle: 'Organize related construction products.',
      selectedNavigationIndex: 2,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: AppSpacing.xl,
                  runSpacing: AppSpacing.sm,
                  children: [
                    Text(
                      '${inventory.categories.length} categories',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text('$activeCount active'),
                    Text('$archivedCount archived'),
                  ],
                ),
              ),
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
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (categories.isEmpty)
            const SizedBox(
              height: 240,
              child: Center(child: Text('No categories match your search.')),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = AppSpacing.lg;
                final columns = constraints.maxWidth >= 1050
                    ? 3
                    : constraints.maxWidth >= 650
                    ? 2
                    : 1;
                final cardWidth =
                    (constraints.maxWidth - (gap * (columns - 1))) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: categories
                      .map(
                        (category) => SizedBox(
                          width: cardWidth,
                          child: InventoryCategoryCard(
                            category: category,
                            productCount: inventory.productCountForCategory(
                              category.id,
                            ),
                            onView: () => _open(category, false),
                            onEdit: () => _open(category, true),
                            onArchive: () => _archive(category),
                          ),
                        ),
                      )
                      .toList(),
                );
              },
            ),
        ],
      ),
    );
  }
}
