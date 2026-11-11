import 'package:client/data/models/category.dart';
import 'package:client/data/models/product.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// One category: rename it, or archive/restore it.
///
/// There is no description field and no Delete. `CategorySerializer` carries
/// `{id, name, is_active}` only, so a description box saved nothing a clerk could
/// ever see again, and the route answers **405** to DELETE — archiving is the
/// supported exit (Phase 4 Tasks 1 and 4).
class InventoryCategoryDialog extends StatefulWidget {
  const InventoryCategoryDialog({
    super.key,
    required this.category,
    required this.products,
    this.editing = false,
  });

  final Category category;
  final List<Product> products;
  final bool editing;

  @override
  State<InventoryCategoryDialog> createState() =>
      _InventoryCategoryDialogState();
}

class _InventoryCategoryDialogState extends State<InventoryCategoryDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.category.name,
  );

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: widget.editing ? Icons.edit_outlined : Icons.category_outlined,
      title: widget.editing ? 'Rename category' : widget.category.name,
      subtitle: widget.editing
          ? widget.category.name
          : '${widget.products.length} '
                '${widget.products.length == 1 ? 'product' : 'products'} filed '
                'under this category',
      // Active or archived is a status, so it sits in the header as words in a
      // badge, not as a colour on its own.
      headerTrailing: widget.editing
          ? null
          : StatusBadge(
              label: widget.category.isActive ? 'Active' : 'Archived',
              tone: widget.category.isActive
                  ? StatusTone.success
                  : StatusTone.neutral,
            ),
      width: 540,
      content: widget.editing
          ? TextFormField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Category name',
                helperText: 'Products keep their place under the new name.',
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DialogSectionLabel('Products (${widget.products.length})'),
                if (widget.products.isEmpty)
                  const Text('No products in this category.')
                else
                  for (final product in widget.products)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.inventory_2_outlined, size: 18),
                      title: Text(product.baseName),
                      subtitle: Text(
                        '${product.variants.length} '
                        'variant${product.variants.length == 1 ? '' : 's'}',
                      ),
                    ),
              ],
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.editing ? 'Cancel' : 'Close'),
        ),
        if (widget.editing)
          FilledButton(
            onPressed: () => Navigator.pop(context, _name.text.trim()),
            child: const Text('Save changes'),
          ),
      ],
    );
  }
}
