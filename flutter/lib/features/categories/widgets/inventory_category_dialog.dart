import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/data/models/category.dart';
import 'package:client/data/models/product.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/status_pill.dart';
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
    return AppDialog(
      icon: widget.editing ? Icons.edit_outlined : Icons.category_outlined,
      title: widget.editing ? 'Edit category' : widget.category.name,
      subtitle: widget.editing
          ? widget.category.name
          : '${widget.products.length} ${widget.products.length == 1 ? 'product' : 'products'} in this category',
      headerTrailing: widget.editing
          ? null
          : StatusPill(
              label: widget.category.isActive ? 'Active' : 'Archived',
              color: widget.category.isActive
                  ? AppColors.success
                  : AppColors.textSecondary,
            ),
      width: 540,
      content: widget.editing
          ? Column(
              children: [
                TextFormField(
                  controller: _name,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Category name'),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextFormField(
                  controller: _description,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.category.description,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                DialogSectionLabel('Products (${widget.products.length})'),
                if (widget.products.isEmpty)
                  const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No products yet',
                    message: 'No products in this category.',
                  )
                else
                  for (final product in widget.products)
                    LineItemTile(
                      title: product.baseName,
                      subtitle: product.brandName,
                      amount: '${product.variants.length} variant(s)',
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
