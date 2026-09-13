import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/product.dart';
import 'package:flutter/material.dart';

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
  late final TextEditingController _description = TextEditingController(
    text: widget.category.description,
  );

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.editing ? 'Edit category' : widget.category.name),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: widget.editing
              ? Column(
                  children: [
                    TextFormField(
                      controller: _name,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Category name',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      controller: _description,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.category.description),
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
            onPressed: () => Navigator.pop(
              context,
              widget.category.copyWith(
                name: _name.text.trim(),
                description: _description.text.trim(),
              ),
            ),
            child: const Text('Save changes'),
          ),
      ],
    );
  }
}
