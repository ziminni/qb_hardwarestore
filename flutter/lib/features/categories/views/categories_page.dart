import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/category.dart';
import 'package:client/features/categories/widgets/inventory_category_card.dart';
import 'package:client/features/categories/widgets/inventory_category_dialog.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Categories, live (Phase 4 Task 4).
///
/// Every action here reaches `GET/POST/PATCH /api/v1/categories/` and reloads.
/// Before this, "Save changes" renamed the row in memory and the snackbar said so
/// in as many words — "Category updated in mock data." — and the change was gone
/// on the next load. There is no Delete anywhere: the route answers **405**, so
/// archiving is the supported exit and a restore is the same PATCH with the
/// other flag.
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    // Load on open. Deferred past the first frame: `load()` notifies
    // synchronously and marking an element dirty mid-build throws.
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

  Future<void> _create() async {
    final inventory = context.read<InventoryViewmodel>();
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _NewCategoryDialog(),
    );
    if (name == null || !mounted) return;
    final error = await inventory.createCategory(name);
    _announce(error ?? 'Category "$name" created.');
  }

  Future<void> _open(Category category, bool editing) async {
    final inventory = context.read<InventoryViewmodel>();
    if (!editing) {
      await showDialog<void>(
        context: context,
        builder: (_) => InventoryCategoryDialog(
          category: category,
          products: inventory.productsForCategory(category.id),
        ),
      );
      return;
    }
    final name = await showDialog<String>(
      context: context,
      builder: (_) => InventoryCategoryDialog(
        category: category,
        products: const [],
        editing: true,
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    final error = await inventory.renameCategory(category.id, name);
    _announce(error ?? 'Category renamed to "$name".');
  }

  Future<void> _toggle(Category category) async {
    final inventory = context.read<InventoryViewmodel>();
    final archiving = category.isActive;
    if (archiving) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Archive category?'),
          content: Text(
            '${category.name} will be hidden from the new product picker. '
            'Products already filed under it stay sellable.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Archive'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final error = await inventory.setCategoryActive(category.id, !archiving);
    _announce(
      error ?? '${category.name} ${archiving ? 'archived' : 'restored'}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    final categories = inventory.categories
        .where((item) => item.name.toLowerCase().contains(_query.toLowerCase()))
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
                width: 320,
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search categories',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: const Text('New category'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          if (inventory.isLoading && !inventory.hasLoaded)
            const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            )
          else if (inventory.loadError case final error?)
            SizedBox(
              height: 240,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(error),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton(
                      onPressed: inventory.load,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (categories.isEmpty)
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
                            onArchive: () => _toggle(category),
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

/// Names a new category. The server takes a name and nothing else.
class _NewCategoryDialog extends StatefulWidget {
  const _NewCategoryDialog();

  @override
  State<_NewCategoryDialog> createState() => _NewCategoryDialogState();
}

class _NewCategoryDialogState extends State<_NewCategoryDialog> {
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a category name.');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New category'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: _name,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Category name',
            errorText: _error,
          ),
          onSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
