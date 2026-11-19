import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/admin/viewmodels/catalogue_lists_viewmodel.dart';
import 'package:client/features/suppliers/widgets/suppliers_form_dialog.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// Admin → Settings → Categories & suppliers (owner 2026-11-18).
///
/// The shop-wide lists every other screen picks from: the product form's
/// category, a purchase order's supplier. Add and edit here; archive to take one
/// out of the pickers while history keeps its name; delete only what nothing
/// uses (the server refuses the rest and says what uses it).
/// One of the two lists, for a screen that gives each its own section.
enum CatalogueList { categories, suppliers }

class CatalogueListsPanel extends StatefulWidget {
  const CatalogueListsPanel({
    super.key,
    this.viewmodel,
    this.canDelete = true,
    this.only,
  });

  final CatalogueListsViewmodel? viewmodel;

  /// Show just this list, with no inner tabs and no panel title (Settings'
  /// side tabs give each list its own section, owner 2026-11-18). Null shows
  /// both behind tabs.
  final CatalogueList? only;

  /// Delete is an Admin action (the server answers 403 to anyone else).
  final bool canDelete;

  @override
  State<CatalogueListsPanel> createState() => _CatalogueListsPanelState();
}

class _CatalogueListsPanelState extends State<CatalogueListsPanel> {
  late final CatalogueListsViewmodel _lists =
      widget.viewmodel ?? CatalogueListsViewmodel();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _lists.load();
  }

  void _say(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _afterWrite(String? error, String done) async {
    if (!mounted) return;
    if (error == null) {
      _say(done);
    } else {
      await showDialog<void>(
        context: context,
        builder: (context) => AppDialog(
          icon: Icons.info_outline,
          title: 'Not saved',
          content: Text(error),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AppDialog(
          icon: Icons.delete_outline,
          title: title,
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              key: const ValueKey('confirm-action'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;

  // ---- Categories -----------------------------------------------------------

  Future<void> _editCategory([Category? category]) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: category == null ? 'Add category' : 'Edit category',
        initial: category?.name ?? '',
      ),
    );
    if (name == null || name.isEmpty) return;
    final error = await _lists.saveCategory(id: category?.id, name: name);
    await _afterWrite(error, category == null ? '$name added.' : 'Saved.');
  }

  Future<void> _deleteCategory(Category category) async {
    if (!await _confirm(
      'Delete ${category.name}?',
      'This cannot be undone. A category that products use cannot be deleted; '
          'archive it instead.',
      'Delete',
    )) {
      return;
    }
    final error = await _lists.deleteCategory(category);
    await _afterWrite(error, '${category.name} deleted.');
  }

  // ---- Suppliers ------------------------------------------------------------

  Future<void> _editSupplier([Supplier? supplier]) async {
    final saved = await showDialog<Supplier>(
      context: context,
      builder: (_) => SuppliersFormDialog(supplier: supplier),
    );
    if (saved == null) return;
    final error = await _lists.saveSupplier(saved);
    await _afterWrite(
      error,
      supplier == null ? '${saved.companyName} added.' : 'Saved.',
    );
  }

  Future<void> _deleteSupplier(Supplier supplier) async {
    if (!await _confirm(
      'Delete ${supplier.companyName}?',
      'This cannot be undone. A supplier with orders, bills or returns cannot '
          'be deleted; archive it instead.',
      'Delete',
    )) {
      return;
    }
    final error = await _lists.deleteSupplier(supplier);
    await _afterWrite(error, '${supplier.companyName} deleted.');
  }

  bool _matches(String text) =>
      _query.trim().isEmpty ||
      text.toLowerCase().contains(_query.trim().toLowerCase());

  Widget _single(CatalogueList list) => AppPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_lists.loadError != null) ...[
          ErrorBanner(message: _lists.loadError!, onRetry: _lists.load),
          const SizedBox(height: AppSpacing.md),
        ],
        TextField(
          onChanged: (value) => setState(() => _query = value),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: list == CatalogueList.categories
                ? 'Search categories'
                : 'Search suppliers',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 520,
          child: _lists.isLoading && _lists.categories.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : list == CatalogueList.categories
              ? _categoryTab()
              : _supplierTab(),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final only = widget.only;
    if (only != null) {
      return ListenableBuilder(
        listenable: _lists,
        builder: (context, _) => _single(only),
      );
    }
    return ListenableBuilder(
      listenable: _lists,
      builder: (context, _) => AppPanel(
        title: 'Categories & suppliers',
        child: DefaultTabController(
          length: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'The lists every screen picks from: product categories and '
                'purchase-order suppliers. Archive to hide one from the pickers '
                'and keep its history; delete only what was never used.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              if (_lists.loadError != null) ...[
                ErrorBanner(message: _lists.loadError!, onRetry: _lists.load),
                const SizedBox(height: AppSpacing.md),
              ],
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'Categories (${_lists.categories.length})'),
                  Tab(text: 'Suppliers (${_lists.suppliers.length})'),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Search',
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: 460,
                child: _lists.isLoading && _lists.categories.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : TabBarView(children: [_categoryTab(), _supplierTab()]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbar(String label, VoidCallback onAdd, Key key) => Align(
    alignment: Alignment.centerLeft,
    child: FilledButton.icon(
      key: key,
      onPressed: _lists.isSaving ? null : onAdd,
      icon: const Icon(Icons.add, size: 18),
      label: Text(label),
    ),
  );

  Widget _categoryTab() {
    final rows = [
      for (final row in _lists.categories)
        if (_matches(row.name)) row,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar('Add category', _editCategory, const ValueKey('add-category')),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No category matches.'))
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return _RowTile(
                      key: ValueKey('category-${row.id}'),
                      title: row.name,
                      subtitle: null,
                      active: row.isActive,
                      busy: _lists.isSaving,
                      canDelete: widget.canDelete,
                      onEdit: () => _editCategory(row),
                      onToggle: () async => _afterWrite(
                        await _lists.setCategoryActive(row, !row.isActive),
                        row.isActive
                            ? '${row.name} archived.'
                            : '${row.name} restored.',
                      ),
                      onDelete: () => _deleteCategory(row),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _supplierTab() {
    final rows = [
      for (final row in _lists.suppliers)
        if (_matches('${row.companyName} ${row.contactPerson} ${row.phone}'))
          row,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _toolbar('Add supplier', _editSupplier, const ValueKey('add-supplier')),
        const SizedBox(height: AppSpacing.sm),
        Expanded(
          child: rows.isEmpty
              ? const Center(child: Text('No supplier matches.'))
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final details = [
                      if (row.contactPerson.isNotEmpty) row.contactPerson,
                      if (row.phone.isNotEmpty) row.phone,
                      if (row.termsDays > 0) 'Terms ${row.termsDays} days',
                    ].join(' · ');
                    return _RowTile(
                      key: ValueKey('supplier-${row.id}'),
                      title: row.companyName,
                      subtitle: details.isEmpty ? null : details,
                      active: row.isActive,
                      busy: _lists.isSaving,
                      canDelete: widget.canDelete,
                      onEdit: () => _editSupplier(row),
                      onToggle: () async => _afterWrite(
                        await _lists.setSupplierActive(row, !row.isActive),
                        row.isActive
                            ? '${row.companyName} archived.'
                            : '${row.companyName} restored.',
                      ),
                      onDelete: () => _deleteSupplier(row),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.active,
    required this.busy,
    required this.canDelete,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final String title;
  final String? subtitle;
  final bool active;
  final bool busy;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    // Its own transparent Material: the panel paints a background, which would
    // otherwise hide the row's hover and tap feedback.
    return Material(type: MaterialType.transparency, child: _tile(context));
  }

  Widget _tile(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: active ? null : AppColors.textSecondary,
        ),
      ),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: Wrap(
        spacing: AppSpacing.xs,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          StatusBadge(
            label: active ? 'Active' : 'Archived',
            tone: active ? StatusTone.success : StatusTone.neutral,
          ),
          IconButton(
            tooltip: 'Edit',
            onPressed: busy ? null : onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: active ? 'Archive' : 'Restore',
            onPressed: busy ? null : onToggle,
            icon: Icon(
              active ? Icons.archive_outlined : Icons.unarchive_outlined,
            ),
          ),
          if (canDelete)
            IconButton(
              tooltip: 'Delete',
              onPressed: busy ? null : onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
    );
  }
}

/// A one-field dialog for a category's name.
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, required this.initial});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Type a name.');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.category_outlined,
      title: widget.title,
      content: TextField(
        key: const ValueKey('category-name'),
        controller: _name,
        autofocus: true,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(labelText: 'Name', errorText: _error),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('category-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
