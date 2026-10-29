import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product_tracking.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_stock_status_badge.dart';
import 'package:client/features/products/widgets/edit_unit_code_dialog.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ProductsDetailsDialog extends StatefulWidget {
  const ProductsDetailsDialog({
    super.key,
    required this.product,
    this.movements = const [],
    this.tracking,
  });

  final Product product;
  final List<InventoryMovement> movements;
  final ProductTrackingConfiguration? tracking;

  @override
  State<ProductsDetailsDialog> createState() => _ProductsDetailsDialogState();
}

class _ProductsDetailsDialogState extends State<ProductsDetailsDialog> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final movements = widget.movements;
    final tracking = widget.tracking;
    final theme = Theme.of(context);
    // Stock, price, cost and location all live outside the variant now: stock on
    // batches, price on the selling unit, cost on the newest batch, location in
    // the local hint store. Decision 02 / 08 / 10.
    final inventory = context.read<InventoryViewmodel>();
    // Code writes are `IsInventoryRole` on the server (decision 18), so the button
    // only exists for those role CODES — `roleName` is the code, never the display
    // label (the Phase 4 Resolve outage compared the label and hid the button from
    // everyone).
    final canEditCodes = const {
      'inventory',
      'sales',
      'admin',
    }.contains(context.read<AuthViewmodel>().roleName);

    return AlertDialog(
      title: Text(product.baseName),
      // The content is taller than a 1366x768 laptop viewport with just a few
      // variants, and the dialog gave it no ceiling: the lower units were clipped
      // with no scrollbar to grab and a wheel that did not move anything (QA
      // defect 4, `qa-browser-assets/e10-dialog-1366x768.png`). A constrained
      // height plus a PERSISTENT thumb makes every selling unit reachable and
      // visibly so — desktop's default thumb only appears on hover.
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: SizedBox(
          width: 780,
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scrollController,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadii.small),
                    child: ProductsImage(
                      imageUrl: product.imageUrl,
                      width: 160,
                      height: 120,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Category', style: theme.textTheme.labelMedium),
                  Text(product.categoryName),
                  const SizedBox(height: AppSpacing.md),
                  Text('Brand', style: theme.textTheme.labelMedium),
                  Text(product.brandName),
                  const SizedBox(height: AppSpacing.md),
                  Text('Description', style: theme.textTheme.labelMedium),
                  Text(
                    product.description.isEmpty
                        ? 'No description provided.'
                        : product.description,
                  ),
                  if (tracking != null) ...[
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      'Inventory Tracking',
                      style: theme.textTheme.titleSmall,
                    ),
                    const Divider(),
                    Wrap(
                      spacing: AppSpacing.xl,
                      runSpacing: AppSpacing.sm,
                      children: [
                        Text('Method: ${tracking.method.label}'),
                        Text('Base unit: ${tracking.baseUnit}'),
                        Text('Stock form: ${tracking.stockForm.label}'),
                        Text(
                          'Total available: ${tracking.totalBaseQuantity.toStringAsFixed(3)} ${tracking.baseUnit}',
                        ),
                        Text('Location: ${tracking.storageLocation}'),
                      ],
                    ),
                    if (tracking.physicalPieces.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Physical pieces',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: tracking.physicalPieces.length,
                          itemBuilder: (context, index) {
                            final remaining = tracking.physicalPieces[index];
                            final full =
                                (remaining - tracking.standardLength).abs() <
                                .0001;
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              title: Text(
                                'Piece #${(index + 1).toString().padLeft(3, '0')}',
                              ),
                              trailing: Text(
                                '${remaining.toStringAsFixed(3)} ${tracking.baseUnit} · ${full ? 'Full' : 'Cut'}',
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Variants (${product.variants.length})',
                    style: theme.textTheme.titleSmall,
                  ),
                  const Divider(),
                  if (product.variants.isEmpty)
                    const Text('No variants added yet.')
                  else
                    for (final variant in product.variants)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      variant.variantName,
                                      style: theme.textTheme.titleSmall,
                                    ),
                                  ),
                                  InventoryStockStatusBadge(
                                    status: inventory.statusForVariant(
                                      variant.id,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              _UnitCodes(
                                variant: variant,
                                canEdit: canEditCodes,
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              Wrap(
                                spacing: AppSpacing.xl,
                                runSpacing: AppSpacing.sm,
                                children: [
                                  Text('Unit: ${variant.baseUomCode}'),
                                  Text(
                                    'Cost: ₱${(inventory.costFor(variant.id) ?? 0).toStringAsFixed(2)}',
                                  ),
                                  Text(
                                    'Selling: ₱${(inventory.priceFor(variant.id) ?? 0).toStringAsFixed(2)}',
                                  ),
                                  Text(
                                    'Stock: ${inventory.stockOnHandFor(variant.id).toStringAsFixed(0)}',
                                  ),
                                  Text(
                                    'Reorder: ${variant.minStockThreshold.toStringAsFixed(0)}',
                                  ),
                                  Text(
                                    'Location: ${inventory.locationHintFor(variant.id)}',
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Stock History (${movements.length})',
                    style: theme.textTheme.titleSmall,
                  ),
                  const Divider(),
                  if (movements.isEmpty)
                    const Text('No stock history yet.')
                  else
                    for (final movement in movements.take(5))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(movement.type.label),
                        subtitle: Text(
                          '${movement.reference} · ${movement.reason}',
                        ),
                        trailing: Text(
                          '${movement.quantityChange > 0 ? '+' : ''}${movement.quantityChange.toStringAsFixed(0)}',
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

/// Every selling unit of one variant: unit · ×factor · code.
///
/// A code belongs to a UNIT, not to the variant (decision 11 F3): the box and the
/// piece inside it carry different codes, and both have to be visible or a box
/// label cannot be checked against anything.
class _UnitCodes extends StatelessWidget {
  const _UnitCodes({required this.variant, required this.canEdit});

  final ProductVariant variant;

  /// True for the role codes the server admits to a code write.
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    if (variant.sellingUoms.isEmpty) {
      return const Text('No selling units yet.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final unit in variant.sellingUoms)
          Row(
            children: [
              Expanded(child: Text(_line(unit))),
              if (canEdit)
                TextButton(
                  onPressed: () => _editCode(context, unit),
                  child: const Text('Edit code'),
                ),
            ],
          ),
      ],
    );
  }

  String _line(VariantUom unit) {
    final factor = unit.conversionFactor;
    final shown = factor == factor.roundToDouble()
        ? factor.toStringAsFixed(0)
        : '$factor';
    final code = unit.barcodeQr.isEmpty ? 'no code yet' : unit.barcodeQr;
    return '${unit.uomCode} · ×$shown · $code';
  }

  Future<void> _editCode(BuildContext context, VariantUom unit) async {
    final inventory = context.read<InventoryViewmodel>();
    await showDialog<void>(
      context: context,
      builder: (_) => EditUnitCodeDialog(
        unitName: unit.uomCode,
        currentCode: unit.barcodeQr,
        // The store writes through the repository and reloads on success; a
        // refusal comes back as the sentence the field shows.
        onSubmit: (code) => inventory.setSellingUnitBarcode(unit.id, code),
      ),
    );
  }
}
