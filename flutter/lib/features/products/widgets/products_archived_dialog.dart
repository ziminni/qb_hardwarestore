import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:flutter/material.dart';

/// Archived products, with a Restore action (Phase 4 Task 4).
///
/// Restoring is `PATCH {"is_active": true}` — the same PATCH that archived it.
/// A product is never deleted, so this list is the only way back for one that was
/// archived by mistake.
class ProductsArchivedDialog extends StatefulWidget {
  const ProductsArchivedDialog({
    super.key,
    required this.products,
    required this.onRestore,
  });

  final List<Product> products;

  /// PATCHes the row back to active. Returns an error message, or null.
  final Future<String?> Function(Product product) onRestore;

  @override
  State<ProductsArchivedDialog> createState() => _ProductsArchivedDialogState();
}

class _ProductsArchivedDialogState extends State<ProductsArchivedDialog> {
  late List<Product> _rows = List.of(widget.products);
  bool _busy = false;

  Future<void> _restore(Product product) async {
    setState(() => _busy = true);
    final error = await widget.onRestore(product);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) {
        _rows = _rows.where((row) => row.id != product.id).toList();
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error ?? '${product.baseName} restored to the catalogue.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final products = _rows;

    return AlertDialog(
      title: const Text('Archived products'),
      content: SizedBox(
        width: 680,
        child: products.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 40,
                      color: colors.outline,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'No archived products',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Products moved to the archive will appear here.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 480),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: products.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadii.small),
                        child: ProductsImage(
                          imageUrl: product.imageUrl,
                          width: 44,
                          height: 44,
                        ),
                      ),
                      title: Text(product.baseName),
                      subtitle: Text(
                        '${product.categoryName} · ${product.brandName} · ${product.variants.length} variant${product.variants.length == 1 ? '' : 's'}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Chip(label: Text('Archived')),
                          const SizedBox(width: AppSpacing.sm),
                          OutlinedButton(
                            onPressed: _busy ? null : () => _restore(product),
                            child: const Text('Restore'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
