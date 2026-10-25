import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/product.dart';
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
    return AlertDialog(
      title: Text(widget.editing ? 'Rename category' : widget.category.name),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: widget.editing
              ? TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Category name'),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.category.isActive ? 'Active' : 'Archived',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Products (${widget.products.length})',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Divider(),
                    if (widget.products.isEmpty)
                      const Text('No products in this category.')
                    else
                      for (final product in widget.products)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.inventory_2_outlined,
                            size: 18,
                          ),
                          title: Text(product.baseName),
                          subtitle: Text(
                            '${product.variants.length} variant(s)',
                          ),
                        ),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
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
