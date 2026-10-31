import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/category.dart';
import 'package:client/features/categories/widgets/inventory_category_card.dart';
import 'package:client/features/categories/widgets/inventory_category_dialog.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Status as the filter offers it: "all" or one of the two flags the server has.
///
/// The value is `null` for "All" so the page holds one nullable field instead of
/// a third state the category model does not have.
const _statusChips = <String, bool?>{
  'All': null,
  'Active': true,
  'Archived': false,
};

/// Categories, live (Phase 4 Task 4).
///
/// Every action here reaches `GET/POST/PATCH /api/v1/categories/` and reloads.
/// Before this, "Save changes" renamed the row in memory and the snackbar said so
/// in as many words — "Category updated in mock data." — and the change was gone
/// on the next load. There is no Delete anywhere: the route answers **405**, so
/// archiving is the supported exit and a restore is the same PATCH with the
/// other flag.
///
/// K3: each card counts the products filed under its category, read off the
/// catalogue the store already loaded, so archiving is an informed choice
/// instead of a blind one.
class CategoriesPage extends StatefulWidget {
  const CategoriesPage({super.key});

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  String _query = '';
  String _statusChip = 'All';

  /// Owned here, not by [FilterBar], because "Clear filters" has to empty it.
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Load on open. Deferred past the first frame: `load()` notifies
    // synchronously and marking an element dirty mid-build throws.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InventoryViewmodel>().load();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _announce(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _clearFilters() {
    _search.clear();
    setState(() {
      _query = '';
      _statusChip = 'All';
    });
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
    // The count is in the question: "1 product" and "24 products" are different
    // decisions, and the card is no longer the only place a clerk can see it.
    final productCount = inventory.productCountForCategory(category.id);
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
    if (error != null) {
      _announce(error);
      return;
    }
    // Products filed under an archived category stay sellable; the count says how
    // many that is, so the clerk is not left guessing.
    final stays = productCount == 1
        ? '1 product stays sellable'
        : '$productCount products stay sellable';
    _announce(
      archiving && productCount > 0
          ? '${category.name} archived. $stays.'
          : '${category.name} ${archiving ? 'archived' : 'restored'}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    final wantedActive = _statusChips[_statusChip];
    final query = _query.trim().toLowerCase();
    final visible = inventory.categories
        .where(
          (item) =>
              item.name.toLowerCase().contains(query) &&
              (wantedActive == null || item.isActive == wantedActive),
        )
        .toList(growable: false);

    final total = inventory.categories.length;
    final activeCount = inventory.categories
        .where((item) => item.isActive)
        .length;
    final archivedCount = total - activeCount;
    final filtering = query.isNotEmpty || wantedActive != null;

    final failure = inventory.loadError;
    // A first load has not answered yet: the spinner belongs to that case only.
    final pending = inventory.isLoading || !inventory.hasLoaded;
    // One failure, never a failure plus an empty state under it.
    final showBanner = failure != null && !pending;

    return InventorySkeletonLayout(
      title: 'Categories',
      subtitle: 'Organize related construction products.',
      selectedNavigationIndex: 2,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: FilterBar(
                  searchController: _search,
                  searchHint: 'Search categories',
                  options: _statusChips.keys.toList(),
                  selected: _statusChip,
                  onSearchChanged: (value) => setState(() => _query = value),
                  onSelected: (label) => setState(() => _statusChip = label),
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
          if (total > 0) ...[
            const SizedBox(height: AppSpacing.md),
            // The count line is only a fact once something is loaded: on a
            // failed or empty read it would claim "0 categories".
            Text(
              '${formatCount(total)} ${total == 1 ? 'category' : 'categories'}, '
              '${formatCount(activeCount)} active, '
              '${formatCount(archivedCount)} archived',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          if (showBanner)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: ErrorBanner(message: failure, onRetry: inventory.load),
            ),
          if (pending && total == 0)
            const AppPanel(
              child: SizedBox(
                height: 120,
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (visible.isEmpty && !showBanner)
            AppPanel(
              child: EmptyState(
                icon: Icons.category_outlined,
                // "Nothing exists yet" and "your filters hide it" are different
                // facts, and the old copy said the second one for both.
                message: filtering
                    ? 'No categories match these filters.'
                    : 'No categories yet.',
                actionLabel: filtering ? 'Clear filters' : null,
                onAction: filtering ? _clearFilters : null,
              ),
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
                // Rows are laid out one at a time so the cards in a row share
                // the height of the tallest: a two-line category name must not
                // leave one card shorter than its neighbours. IntrinsicHeight
                // derives that height from the content, so nothing is
                // hard-coded and a longer name simply makes a taller row.
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (
                      var start = 0;
                      start < visible.length;
                      start += columns
                    )
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: start + columns < visible.length ? gap : 0,
                        ),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var slot = 0; slot < columns; slot++) ...[
                                if (slot > 0) const SizedBox(width: gap),
                                Expanded(
                                  child: start + slot < visible.length
                                      ? _card(visible[start + slot], inventory)
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _card(Category category, InventoryViewmodel inventory) {
    return InventoryCategoryCard(
      category: category,
      productCount: inventory.productCountForCategory(category.id),
      onView: () => _open(category, false),
      onEdit: () => _open(category, true),
      onArchive: () => _toggle(category),
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
