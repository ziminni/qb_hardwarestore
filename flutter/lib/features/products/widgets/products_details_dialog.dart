import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/product_writes.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_stock_status_badge.dart';
import 'package:client/features/products/widgets/edit_unit_code_dialog.dart';
import 'package:client/features/products/widgets/products_image.dart';
import 'package:client/features/products/widgets/selling_unit_fields.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class ProductsDetailsDialog extends StatefulWidget {
  const ProductsDetailsDialog({
    super.key,
    required this.product,
    this.movements = const [],
  });

  final Product product;
  final List<InventoryMovement> movements;

  @override
  State<ProductsDetailsDialog> createState() => _ProductsDetailsDialogState();
}

class _ProductsDetailsDialogState extends State<ProductsDetailsDialog> {
  final _scrollController = ScrollController();

  /// The server's sentence when a removal or an added unit was refused. Shown
  /// above the list, which the refusal reloaded.
  String? _actionError;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final inventory = context.watch<InventoryViewmodel>();
    // Code writes are `IsInventoryRole` on the server (decision 18), so the
    // buttons only exist for those role CODES — `roleName` is the code, never
    // the display label.
    final canEdit = const {
      'inventory',
      'sales',
      'admin',
    }.contains(context.read<AuthViewmodel>().roleName);

    return AppDialog(
      icon: Icons.inventory_2_outlined,
      title: product.baseName,
      subtitle: '${product.categoryName} · ${product.brandName}',
      width: 780,
      scrollable: false,
      content: ConstrainedBox(
        // Taller than a 1366x768 laptop viewport with a few variants, so the
        // content scrolls with a PERSISTENT thumb the mouse can grab (QA defect
        // 4: a hover-only thumb was invisible and the wheel did nothing).
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_actionError != null) ...[
                  ErrorBanner(message: _actionError!),
                  const SizedBox(height: AppSpacing.lg),
                ],
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadii.small),
                  child: ProductsImage(
                    imageUrl: product.imageUrl,
                    width: 160,
                    height: 120,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                DetailRow(label: 'Category', value: product.categoryName),
                DetailRow(label: 'Brand', value: product.brandName),
                DetailRow(
                  label: 'Description',
                  value: product.description.isEmpty
                      ? 'No description provided.'
                      : product.description,
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Variants (${product.variants.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Divider(),
                if (product.variants.isEmpty)
                  const Text('No variants added yet.')
                else
                  for (final snapshotVariant in product.variants)
                    // The dialog reloads after a write, so read the CURRENT row
                    // from the store rather than the snapshot it opened with.
                    _variantCard(
                      context,
                      inventory,
                      inventory.variantFor(snapshotVariant.id) ??
                          snapshotVariant,
                      canEdit: canEdit,
                    ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  'Stock History (${widget.movements.length})',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Divider(),
                if (widget.movements.isEmpty)
                  const Text('No stock history yet.')
                else
                  for (final movement in widget.movements.take(5))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(movement.type.label),
                      subtitle: Text(
                        '${movement.reference} · ${movement.reason}',
                      ),
                      trailing: Text(
                        formatSignedQuantity(movement.quantityChange),
                      ),
                    ),
              ],
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

  Widget _variantCard(
    BuildContext context,
    InventoryViewmodel inventory,
    ProductVariant variant, {
    required bool canEdit,
  }) {
    final theme = Theme.of(context);
    final location = inventory.locationHintFor(variant.id);
    return Card(
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
                  status: inventory.statusForVariant(variant.id),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.xl,
              runSpacing: AppSpacing.sm,
              children: [
                Text('Unit: ${variant.baseUomCode}'),
                Text(
                  'Cost: ${formatPeso((inventory.costFor(variant.id) ?? 0))}',
                ),
                Text(
                  'Stock: ${formatQuantity(inventory.stockOnHandFor(variant.id))}',
                ),
                Text('Reorder: ${formatQuantity(variant.minStockThreshold)}'),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              location.isEmpty
                  ? 'Storage location: Not recorded on this device'
                  : 'Storage location: $location',
            ),
            Text(
              // The server has no location field (decision 15): never imply it
              // does, and never show one till as another till's knowledge.
              'Saved on this device only',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            const DialogSectionLabel('Selling units'),
            if (variant.sellingUoms.isEmpty)
              const Text('No selling units yet.')
            else
              for (final unit in variant.sellingUoms)
                _unitRow(context, variant, unit, canEdit: canEdit),
            if (canEdit) ...[
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                key: ValueKey('add-selling-unit-${variant.id}'),
                onPressed: () => _addUnit(context, variant),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add selling unit'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _unitRow(
    BuildContext context,
    ProductVariant variant,
    VariantUom unit, {
    required bool canEdit,
  }) {
    final code = unit.barcodeQr.isEmpty ? 'No code yet' : unit.barcodeQr;
    // Base identity is the variant's own unit at factor 1, never list order: a
    // bag that sorts first is still a package, and the base unit can never be
    // removed whatever its position.
    final isBase =
        unit.uomId == variant.baseUomId && unit.conversionFactor == 1;
    final canRemove = canEdit && !isBase && !unit.inUse;
    return Container(
      key: ValueKey('unit-${unit.id}'),
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${unit.uomCode} · ×${formatQuantity(unit.conversionFactor)} · '
            '${formatPeso(unit.defaultSellingPrice)}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            // Words, never colour alone: a whole unit takes ones, a measured
            // unit takes fractions (the server enforces it).
            '${unit.uomIsWhole ? 'Whole' : 'Measured'} · $code',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (canEdit || canRemove)
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                if (canEdit)
                  TextButton(
                    onPressed: () => _editCode(context, unit),
                    child: const Text('Edit code'),
                  ),
                if (canRemove)
                  TextButton(
                    key: ValueKey('remove-unit-${unit.id}'),
                    onPressed: () => _removeUnit(context, variant, unit),
                    child: const Text('Remove'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _addUnit(BuildContext context, ProductVariant variant) {
    final inventory = context.read<InventoryViewmodel>();
    return showDialog<void>(
      context: context,
      builder: (_) => _AddSellingUnitDialog(
        productName: widget.product.baseName,
        variant: variant,
        units: inventory.units,
        // The same store path every catalog write uses; it writes and reloads.
        onSubmit: (unit) => inventory.addSellingUnit(variant.id, unit),
      ),
    );
  }

  Future<void> _removeUnit(
    BuildContext context,
    ProductVariant variant,
    VariantUom unit,
  ) async {
    final inventory = context.read<InventoryViewmodel>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Remove ${unit.uomName} '
          '(${formatQuantity(unit.conversionFactor)} '
          '${variant.baseUomCode})?',
        ),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Remove unit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionError = null);
    final error = await inventory.removeSellingUnit(unit.id);
    if (!mounted) return;
    // A refusal reloaded the list (the server disagreed with this snapshot); on
    // success the reloaded list simply no longer holds the unit.
    setState(() => _actionError = error);
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

/// Adds one selling unit to an existing variant, with the SAME fields and rules
/// as Add product's step 2 (decision 16).
///
/// A refused POST keeps the dialog open on the server's sentence, because closing
/// would leave the clerk with a message and no way to correct the row.
class _AddSellingUnitDialog extends StatefulWidget {
  const _AddSellingUnitDialog({
    required this.productName,
    required this.variant,
    required this.units,
    required this.onSubmit,
  });

  final String productName;
  final ProductVariant variant;
  final List<UnitOfMeasure> units;
  final Future<String?> Function(NewSellingUnit unit) onSubmit;

  @override
  State<_AddSellingUnitDialog> createState() => _AddSellingUnitDialogState();
}

class _AddSellingUnitDialogState extends State<_AddSellingUnitDialog> {
  final _formKey = GlobalKey<FormState>();
  final _draft = SellingUnitDraft();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final unit = NewSellingUnit(
      uomId: _draft.uomId!,
      uomCode: _codeFor(_draft.uomId),
      conversionFactor: double.parse(_draft.factor.text.trim()),
      sellingPrice: double.parse(_draft.price.text.trim()),
      barcodeQr: _draft.code.text.trim(),
    );
    final message = await widget.onSubmit(unit);
    if (!mounted) return;
    if (message != null) {
      setState(() {
        _error = message;
        _saving = false;
      });
      return;
    }
    Navigator.pop(context);
  }

  String _codeFor(int? uomId) {
    for (final unit in widget.units) {
      if (unit.id == uomId) return unit.code;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.add_box_outlined,
      title: 'Add selling unit',
      subtitle: '${widget.productName} · ${widget.variant.variantName}',
      width: 520,
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.lg),
            ],
            SellingUnitFields(
              draft: _draft,
              index: 0,
              keyPrefix: 'add',
              baseCode: widget.variant.baseUomCode,
              units: widget.units,
              validateUnit: (value) => sellingUnitUnitError(
                value,
                baseUomId: widget.variant.baseUomId,
                usedUomIds: [
                  for (final unit in widget.variant.sellingUoms) unit.uomId,
                ],
              ),
              validateFactor: (raw) => sellingUnitFactorError(
                raw,
                baseCode: widget.variant.baseUomCode,
              ),
              validatePrice: sellingUnitPriceError,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('Add unit'),
        ),
      ],
    );
  }
}
