import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// Archived products, with a Restore action (Phase 4 Task 4).
///
/// Restoring is `PATCH {"is_active": true}` — the same PATCH that archived it.
/// A product is never deleted, so this list is the only way back for one that was
/// archived by mistake.
///
/// Phase 1d Task 10a: it wears the shared dialog family (decision 17), so it
/// looks like the rest of the app's dialogs and closes on Esc.
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
    final rows = _rows;

    return AppDialog(
      icon: Icons.archive_outlined,
      title: 'Archived products',
      subtitle: rows.isEmpty
          ? 'Archived products are kept, never deleted.'
          : '${formatCount(rows.length)} archived '
                '${rows.length == 1 ? 'product' : 'products'}, kept and '
                'restorable.',
      width: 700,
      // The list owns its height and scrolling, so the frame must not wrap it in
      // another scroll view.
      scrollable: false,
      content: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 40,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'No archived products',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  const Text('Products moved to the archive will appear here.'),
                ],
              ),
            )
          : ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.6,
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: rows.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final product = rows[index];
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
                      '${product.categoryName} · ${product.brandName} · '
                      '${product.variants.length} '
                      'variant${product.variants.length == 1 ? '' : 's'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // An archived row says so in words plus color, the
                        // same pill as every other status in the app.
                        const StatusBadge(
                          label: 'Archived',
                          tone: StatusTone.neutral,
                        ),
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
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
