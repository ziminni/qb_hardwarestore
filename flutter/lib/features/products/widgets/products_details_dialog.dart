import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
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
    // buttons only exist for those role CODES. Phase 2 F3: the gate asks the
    // areas the account HOLDS, so a merged account keeps them.
    final canEdit = context.read<AuthViewmodel>().hasAnyArea(const {
      'inventory',
      'sales',
      'admin',
    });

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
                // Phase 5 B4: the SERVER's pick-up point. Shown as its own row and
                // kept apart from the device-only shelf note in each variant card,
                // because one is shared with every till and the other is not.
                if (product.storedAtName.trim().isNotEmpty)
                  DetailRow(label: 'Stored at', value: product.storedAtName),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  '${unit.uomCode} · ×${formatQuantity(unit.conversionFactor)} · '
                  '${formatPeso(unit.defaultSellingPrice)}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (isBase)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Base',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          if (!isBase) ...[
            const SizedBox(height: 2),
            Text(
              unit.conversionFactor < 1
                  ? '1 ${unit.uomCode} = ${formatQuantity(unit.conversionFactor)} ${variant.baseUomCode} '
                        '(${formatQuantity(1 / unit.conversionFactor)} ${unit.uomCode} = 1 ${variant.baseUomCode})'
                  : '1 ${unit.uomCode} = ${formatQuantity(unit.conversionFactor)} ${variant.baseUomCode}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            // Words, never colour alone: a whole unit takes ones, a measured
            // unit takes fractions (the server enforces it).
            '${unit.uomIsWhole ? 'Whole' : 'Measured'} · $code'
            '${unit.hasCreditMarkup ? ' · Utang ${formatPeso(unit.creditSellingPrice)}' : ''}',
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
                if (canEdit)
                  TextButton(
                    key: ValueKey('price-history-unit-${unit.id}'),
                    onPressed: () => _showPriceHistory(context, variant, unit),
                    child: const Text('Price history'),
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

  Future<void> _showPriceHistory(
    BuildContext context,
    ProductVariant variant,
    VariantUom unit,
  ) {
    return showDialog<void>(
      context: context,
      builder: (_) => _PriceHistoryDialog(
        title: '${widget.product.baseName} · ${variant.variantName}',
        unitLabel:
            '${unit.uomCode} (×${formatQuantity(unit.conversionFactor)})',
        variantUomId: unit.id,
      ),
    );
  }

  Future<void> _addUnit(BuildContext context, ProductVariant variant) {
    final inventory = context.read<InventoryViewmodel>();
    return showDialog<void>(
      context: context,
      builder: (_) => AddSellingUnitDialog(
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

class _PriceHistoryEntry {
  const _PriceHistoryEntry({
    required this.oldPrice,
    required this.newPrice,
    required this.changedAt,
    required this.actor,
    required this.source,
  });

  final double? oldPrice;
  final double newPrice;
  final DateTime? changedAt;
  final String? actor;
  final String source;

  factory _PriceHistoryEntry.fromJson(Map<String, dynamic> json) {
    double? parseOpt(Object? v) {
      if (v == null) return null;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    return _PriceHistoryEntry(
      oldPrice: parseOpt(json['old_price']),
      newPrice: parseOpt(json['new_price']) ?? 0,
      changedAt: json['changed_at'] is String
          ? DateTime.tryParse(json['changed_at'] as String)
          : null,
      actor: json['actor'] as String?,
      source: (json['source'] as String? ?? '').toUpperCase(),
    );
  }
}

class _PriceHistoryDialog extends StatefulWidget {
  const _PriceHistoryDialog({
    required this.title,
    required this.unitLabel,
    required this.variantUomId,
  });

  final String title;
  final String unitLabel;
  final int variantUomId;

  @override
  State<_PriceHistoryDialog> createState() => _PriceHistoryDialogState();
}

class _PriceHistoryDialogState extends State<_PriceHistoryDialog> {
  late Future<List<_PriceHistoryEntry>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<_PriceHistoryEntry>> _load() async {
    final response = await ApiClient.instance.dio.get<dynamic>(
      '/api/v1/variant-uoms/${widget.variantUomId}/price-history/',
    );
    final data = response.data;
    final rows = data is Map<String, dynamic> && data['results'] is List
        ? data['results'] as List<dynamic>
        : (data is List ? data : const <dynamic>[]);
    return [
      for (final row in rows)
        if (row is Map<String, dynamic>) _PriceHistoryEntry.fromJson(row),
    ];
  }

  String _sourceLabel(String source) => switch (source) {
    'CATALOGUE' => 'Catalogue',
    'IMPORT' => 'Excel import',
    'ADMIN' => 'Admin',
    _ => source.isEmpty ? 'System' : source,
  };

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.history,
      title: 'Price History',
      subtitle: '${widget.title} · ${widget.unitLabel}',
      width: 560,
      content: FutureBuilder<List<_PriceHistoryEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return ErrorBanner(
              message: 'Could not load price history.',
              onRetry: () => setState(() => _future = _load()),
            );
          }
          final entries = snapshot.data ?? const [];
          if (entries.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: Text(
                'No price changes recorded yet for this selling unit.',
              ),
            );
          }
          return ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 360),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: entries.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = entries[index];
                final priceLine = item.oldPrice == null
                    ? 'Initial price: ${formatPeso(item.newPrice)}'
                    : '${formatPeso(item.oldPrice!)} → ${formatPeso(item.newPrice)}';
                final when = item.changedAt != null
                    ? formatDateTime(item.changedAt!.toLocal())
                    : '';
                final who = item.actor != null && item.actor!.isNotEmpty
                    ? 'by ${item.actor}'
                    : '';
                final meta = [
                  _sourceLabel(item.source),
                  if (who.isNotEmpty) who,
                  if (when.isNotEmpty) when,
                ].join(' · ');
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    priceLine,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(meta),
                );
              },
            ),
          );
        },
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
