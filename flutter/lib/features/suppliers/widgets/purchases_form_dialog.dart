import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/purchase_draft.dart';
import 'package:client/data/models/supplier.dart';
import 'package:flutter/material.dart';

/// What the purchase-order dialog produced: the draft, and whether the user
/// asked for it to be placed immediately.
///
/// "Place order" is not a flag on the create request — `POST /purchase-orders/`
/// makes a DRAFT and `place/` is a separate, audited transition — so the dialog
/// reports the user's intent and the viewmodel makes the second call.
class PurchaseOrderFormResult {
  const PurchaseOrderFormResult({required this.draft, required this.place});

  final PurchaseOrderDraft draft;
  final bool place;
}

/// New purchase order (Phase 4 Task 4).
///
/// Everything it shows comes from the server: suppliers from
/// `GET /suppliers/`, materials from the live catalogue, and the suggested unit
/// cost from the newest batch's landed cost (decision 08 — that is the displayed
/// cost, not a charging price). [costFor] is passed in rather than read from a
/// provider because a dialog lives outside the page's provider scope; the page
/// owns that lookup.
///
/// [initialVariantId] / [initialQuantity] are how the Low-stock screen's
/// "Reorder" button prefills the order instead of opening an empty form.
class PurchasesFormDialog extends StatefulWidget {
  const PurchasesFormDialog({
    super.key,
    required this.suppliers,
    required this.products,
    required this.costFor,
    this.initialVariantId,
    this.initialQuantity,
    this.initialSupplierId,
  });

  final List<Supplier> suppliers;
  final List<Product> products;
  final double Function(int variantId) costFor;
  final int? initialVariantId;
  final double? initialQuantity;
  final int? initialSupplierId;

  @override
  State<PurchasesFormDialog> createState() => _PurchasesFormDialogState();
}

class _PurchaseOrderLineForm {
  _PurchaseOrderLineForm({
    required this.variant,
    required this.quantity,
    required this.unitCost,
  });

  final ProductVariant variant;
  final TextEditingController quantity;
  final TextEditingController unitCost;

  void dispose() {
    quantity.dispose();
    unitCost.dispose();
  }
}

class _PurchasesFormDialogState extends State<PurchasesFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _notesController = TextEditingController();
  final List<_PurchaseOrderLineForm> _lines = [];

  late int? _supplierId =
      widget.initialSupplierId ??
      widget.suppliers.where((s) => s.isActive).firstOrNull?.id;
  DateTime? _expectedDelivery;
  String _query = '';
  String? _selectionError;

  @override
  void initState() {
    super.initState();
    final variant = _variantById(widget.initialVariantId);
    if (variant != null) {
      _addLine(variant, quantity: widget.initialQuantity);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  List<({Product product, ProductVariant variant})> get _materials => [
    for (final product in widget.products)
      if (product.isActive)
        for (final variant in product.variants)
          if (variant.isActive) (product: product, variant: variant),
  ];

  ProductVariant? _variantById(int? id) {
    if (id == null) return null;
    for (final material in _materials) {
      if (material.variant.id == id) return material.variant;
    }
    return null;
  }

  String _productNameFor(ProductVariant variant) {
    for (final material in _materials) {
      if (material.variant.id == variant.id) return material.product.baseName;
    }
    return '';
  }

  List<({Product product, ProductVariant variant})> get _filteredMaterials {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _materials;
    return _materials
        .where(
          (item) =>
              item.product.baseName.toLowerCase().contains(query) ||
              item.product.categoryName.toLowerCase().contains(query) ||
              item.product.brandName.toLowerCase().contains(query) ||
              item.variant.variantName.toLowerCase().contains(query) ||
              item.variant.barcode.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  bool _isSelected(int variantId) =>
      _lines.any((line) => line.variant.id == variantId);

  void _toggleMaterial(ProductVariant variant) {
    setState(() {
      _selectionError = null;
      final index = _lines.indexWhere((line) => line.variant.id == variant.id);
      if (index >= 0) {
        _lines.removeAt(index).dispose();
      } else {
        _addLine(variant);
      }
    });
  }

  void _addLine(ProductVariant variant, {double? quantity}) {
    _lines.add(
      _PurchaseOrderLineForm(
        variant: variant,
        quantity: TextEditingController(
          text: (quantity ?? 1).toStringAsFixed(0),
        ),
        unitCost: TextEditingController(
          text: widget.costFor(variant.id).toStringAsFixed(2),
        ),
      ),
    );
  }

  double get _orderTotal => _lines.fold(
    0,
    (sum, line) =>
        sum +
        (double.tryParse(line.quantity.text) ?? 0) *
            (double.tryParse(line.unitCost.text) ?? 0),
  );

  void _submit({required bool place}) {
    if (_supplierId == null) {
      setState(() => _selectionError = 'Choose a supplier first.');
      return;
    }
    if (_lines.isEmpty) {
      setState(() => _selectionError = 'Select at least one material.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final lines = <PurchaseOrderLineDraft>[];
    for (final line in _lines) {
      lines.add(
        PurchaseOrderLineDraft(
          variantId: line.variant.id,
          quantity: double.tryParse(line.quantity.text.trim()) ?? 0,
          unitCost: double.tryParse(line.unitCost.text.trim()) ?? 0,
          variantName: line.variant.variantName,
        ),
      );
    }
    Navigator.pop(
      context,
      PurchaseOrderFormResult(
        draft: PurchaseOrderDraft(
          supplierId: _supplierId!,
          expectedDelivery: _expectedDelivery,
          notes: _notesController.text.trim(),
          lines: lines,
        ),
        place: place,
      ),
    );
  }

  Future<void> _pickExpectedDelivery() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDelivery ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _expectedDelivery = picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final filteredMaterials = _filteredMaterials;
    final activeSuppliers = widget.suppliers
        .where((supplier) => supplier.isActive)
        .toList();

    return AlertDialog(
      title: const Text('New purchase order'),
      content: SizedBox(
        width: 900,
        height: (MediaQuery.sizeOf(context).height - 190).clamp(400.0, 620.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      isExpanded: true,
                      initialValue: _supplierId,
                      decoration: const InputDecoration(labelText: 'Supplier'),
                      items: activeSuppliers
                          .map(
                            (supplier) => DropdownMenuItem(
                              value: supplier.id,
                              child: Text(
                                supplier.companyName,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      validator: (value) =>
                          value == null ? 'Choose a supplier.' : null,
                      onChanged: (value) => setState(() => _supplierId = value),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _pickExpectedDelivery,
                      icon: const Icon(Icons.event_outlined),
                      label: Text(
                        _expectedDelivery == null
                            ? 'Expected delivery (optional)'
                            : PurchaseOrderDraft(
                                    supplierId: _supplierId ?? 0,
                                    lines: const [],
                                    expectedDelivery: _expectedDelivery,
                                  ).toJson()['expected_delivery']
                                  as String,
                      ),
                    ),
                  ),
                ],
              ),
              if (activeSuppliers.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    'No active supplier. Add one on the Suppliers screen first.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.error,
                    ),
                  ),
                ),
              const SizedBox(height: AppSpacing.lg),
              if (_selectionError case final error?)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    error,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.error,
                    ),
                  ),
                ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _cataloguePane(theme, filteredMaterials)),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(child: _linesPane(theme, colors)),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  hintText: 'Optional instructions for this order',
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
        OutlinedButton(
          onPressed: () => _submit(place: false),
          child: const Text('Save draft'),
        ),
        FilledButton.icon(
          onPressed: () => _submit(place: true),
          icon: const Icon(Icons.send_outlined),
          label: const Text('Place order'),
        ),
      ],
    );
  }

  Widget _cataloguePane(
    ThemeData theme,
    List<({Product product, ProductVariant variant})> filteredMaterials,
  ) {
    final colors = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Search material, variant, or barcode',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              '${filteredMaterials.length} materials',
              style: theme.textTheme.labelMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: filteredMaterials.isEmpty
                ? const Center(child: Text('No materials found.'))
                : ListView.separated(
                    itemCount: filteredMaterials.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = filteredMaterials[index];
                      final selected = _isSelected(item.variant.id);
                      return ListTile(
                        selected: selected,
                        onTap: () => _toggleMaterial(item.variant),
                        leading: Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.inventory_2_outlined,
                          color: selected
                              ? colors.primary
                              : colors.onSurfaceVariant,
                        ),
                        title: Text(
                          item.product.baseName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${item.variant.variantName}'
                          '${item.variant.barcode.isEmpty ? '' : ' · ${item.variant.barcode}'}'
                          '\n${formatPeso(widget.costFor(item.variant.id))}'
                          ' / ${item.variant.baseUomCode}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _linesPane(ThemeData theme, ColorScheme colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLowest,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Order lines',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Badge(label: Text('${_lines.length}')),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _lines.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(AppSpacing.xl),
                      child: Text(
                        'Pick materials from the catalogue to add them to this order.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: _lines.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (context, index) {
                      final line = _lines[index];
                      return Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(AppRadii.small),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _productNameFor(line.variant).isEmpty
                                        ? line.variant.variantName
                                        : _productNameFor(line.variant),
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remove line',
                                  onPressed: () =>
                                      _toggleMaterial(line.variant),
                                  icon: const Icon(Icons.close, size: 18),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    key: ValueKey('po-qty-${line.variant.id}'),
                                    controller: line.quantity,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: InputDecoration(
                                      labelText: 'Quantity',
                                      suffixText: line.variant.baseUomCode,
                                      isDense: true,
                                    ),
                                    validator: _positiveNumber,
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: TextFormField(
                                    key: ValueKey('po-cost-${line.variant.id}'),
                                    controller: line.unitCost,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Unit cost',
                                      prefixText: '₱ ',
                                      isDense: true,
                                    ),
                                    validator: _nonNegativeNumber,
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Order total'),
                Text(
                  formatPeso(_orderTotal),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String? _positiveNumber(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed <= 0) return 'Above 0';
    return null;
  }

  static String? _nonNegativeNumber(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 0) return 'Not negative';
    return null;
  }
}
