import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';

class PurchasesFormDialog extends StatefulWidget {
  const PurchasesFormDialog({
    super.key,
    required this.suppliers,
    required this.products,
  });

  final List<Supplier> suppliers;
  final List<Product> products;

  @override
  State<PurchasesFormDialog> createState() => _PurchasesFormDialogState();
}

class _PurchasesFormDialogState extends State<PurchasesFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _notesController = TextEditingController();
  final Map<int, double> _selectedQuantities = {};

  late int _supplierId = widget.suppliers
      .firstWhere((supplier) => supplier.isActive)
      .id;
  String _query = '';
  String? _selectionError;

  List<({Product product, ProductVariant variant})> get _materials => [
    for (final product in widget.products)
      if (product.isActive)
        for (final variant in product.variants)
          if (variant.isActive) (product: product, variant: variant),
  ];

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
              item.variant.sku.toLowerCase().contains(query) ||
              item.variant.qrIdentifier.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  List<({Product product, ProductVariant variant})> get _selectedMaterials =>
      _materials
          .where((item) => _selectedQuantities.containsKey(item.variant.id))
          .toList(growable: false);

  double get _orderTotal => _selectedMaterials.fold(
    0,
    (sum, item) =>
        sum +
        item.variant.costPrice * (_selectedQuantities[item.variant.id] ?? 0),
  );

  @override
  void dispose() {
    _searchController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _toggleMaterial(ProductVariant variant) {
    setState(() {
      if (_selectedQuantities.containsKey(variant.id)) {
        _selectedQuantities.remove(variant.id);
      } else {
        _selectedQuantities[variant.id] = 1;
      }
      _selectionError = null;
    });
  }

  void _submit() {
    if (_selectedQuantities.isEmpty) {
      setState(() => _selectionError = 'Select at least one material.');
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final supplier = widget.suppliers.firstWhere(
      (item) => item.id == _supplierId,
    );
    Navigator.pop(
      context,
      PurchaseOrder(
        id: 0,
        supplierId: supplier.id,
        supplierName: supplier.companyName,
        orderDate: DateTime.now(),
        expectedDelivery: DateTime.now().add(const Duration(days: 7)),
        status: PurchaseStatus.draft,
        createdBy: 'Inventory Staff',
        notes: _notesController.text.trim(),
        items: _selectedMaterials
            .map(
              (item) => PurchaseItem(
                productName: item.product.baseName,
                variantName: item.variant.variantName,
                sku: item.variant.sku,
                quantity: _selectedQuantities[item.variant.id]!,
                receivedQuantity: 0,
                unitCost: item.variant.costPrice,
              ),
            )
            .toList(growable: false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final filteredMaterials = _filteredMaterials;
    final selectedMaterials = _selectedMaterials;

    return AppDialog(
      icon: Icons.add_shopping_cart_rounded,
      title: 'Create Purchase Order',
      subtitle: 'Choose a supplier and the materials to order',
      width: 920,
      scrollable: false,
      content: SizedBox(
        height: (MediaQuery.sizeOf(context).height - 300).clamp(300.0, 560.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _supplierId,
                decoration: const InputDecoration(labelText: 'Supplier'),
                items: widget.suppliers
                    .where((item) => item.isActive)
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.id,
                        child: Text(item.companyName),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _supplierId = value);
                },
              ),
              const SizedBox(height: AppSpacing.lg),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
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
                                autofocus: true,
                                onChanged: (value) =>
                                    setState(() => _query = value),
                                decoration: InputDecoration(
                                  hintText: 'Search material, SKU, or barcode',
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.md,
                              ),
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
                                  ? const Center(
                                      child: Text('No materials found.'),
                                    )
                                  : ListView.separated(
                                      itemCount: filteredMaterials.length,
                                      separatorBuilder: (_, _) =>
                                          const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final item = filteredMaterials[index];
                                        final selected = _selectedQuantities
                                            .containsKey(item.variant.id);
                                        return Material(
                                          color: selected
                                              ? AppColors.selected
                                              : Colors.transparent,
                                          child: ListTile(
                                            selected: selected,
                                            onTap: () =>
                                                _toggleMaterial(item.variant),
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
                                              '${item.variant.variantName} · ${item.variant.sku}\n₱${item.variant.costPrice.toStringAsFixed(2)} / ${item.variant.baseUomCode}',
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            trailing: selected
                                                ? const Text('Selected')
                                                : const Icon(
                                                    Icons.add_circle_outline,
                                                  ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLowest,
                          border: Border.all(
                            color: _selectionError == null
                                ? AppColors.border
                                : colors.error,
                          ),
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
                                      'Selected Materials',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                  ),
                                  Badge(
                                    label: Text('${selectedMaterials.length}'),
                                  ),
                                ],
                              ),
                            ),
                            if (_selectionError != null)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  AppSpacing.md,
                                  0,
                                  AppSpacing.md,
                                  AppSpacing.sm,
                                ),
                                child: Text(
                                  _selectionError!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: colors.error,
                                  ),
                                ),
                              ),
                            const Divider(height: 1),
                            Expanded(
                              child: selectedMaterials.isEmpty
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(AppSpacing.xl),
                                        child: Text(
                                          'Click materials from the catalog to add them to this purchase order.',
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    )
                                  : ListView.separated(
                                      padding: const EdgeInsets.all(
                                        AppSpacing.md,
                                      ),
                                      itemCount: selectedMaterials.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(height: AppSpacing.md),
                                      itemBuilder: (context, index) {
                                        final item = selectedMaterials[index];
                                        return Container(
                                          padding: const EdgeInsets.all(
                                            AppSpacing.md,
                                          ),
                                          decoration: BoxDecoration(
                                            color: colors.surface,
                                            border: Border.all(
                                              color: AppColors.border,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              AppRadii.small,
                                            ),
                                          ),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      item.product.baseName,
                                                      style: theme
                                                          .textTheme
                                                          .titleSmall
                                                          ?.copyWith(
                                                            fontWeight:
                                                                FontWeight.w700,
                                                          ),
                                                    ),
                                                  ),
                                                  IconButton(
                                                    tooltip: 'Remove material',
                                                    onPressed: () =>
                                                        _toggleMaterial(
                                                          item.variant,
                                                        ),
                                                    icon: const Icon(
                                                      Icons.close,
                                                      size: 18,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Text(
                                                '${item.variant.variantName} · ${item.variant.sku}',
                                                style:
                                                    theme.textTheme.bodySmall,
                                              ),
                                              const SizedBox(
                                                height: AppSpacing.sm,
                                              ),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: TextFormField(
                                                      key: ValueKey(
                                                        item.variant.id,
                                                      ),
                                                      initialValue:
                                                          _selectedQuantities[item
                                                                  .variant
                                                                  .id]
                                                              ?.toStringAsFixed(
                                                                0,
                                                              ),
                                                      keyboardType:
                                                          const TextInputType.numberWithOptions(
                                                            decimal: true,
                                                          ),
                                                      decoration:
                                                          InputDecoration(
                                                            labelText:
                                                                'Quantity',
                                                            suffixText: item
                                                                .variant
                                                                .baseUomCode,
                                                            isDense: true,
                                                          ),
                                                      validator: (value) {
                                                        final quantity =
                                                            double.tryParse(
                                                              value ?? '',
                                                            );
                                                        return quantity ==
                                                                    null ||
                                                                quantity <= 0
                                                            ? 'Required'
                                                            : null;
                                                      },
                                                      onChanged: (value) {
                                                        _selectedQuantities[item
                                                                .variant
                                                                .id] =
                                                            double.tryParse(
                                                              value,
                                                            ) ??
                                                            0;
                                                        setState(() {});
                                                      },
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                    width: AppSpacing.md,
                                                  ),
                                                  SizedBox(
                                                    width: 112,
                                                    child: Text(
                                                      '₱${(item.variant.costPrice * (_selectedQuantities[item.variant.id] ?? 0)).toStringAsFixed(2)}',
                                                      textAlign: TextAlign.end,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
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
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text('Order total'),
                                  Text(
                                    '₱${_orderTotal.toStringAsFixed(2)}',
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.save_outlined),
          label: Text(
            selectedMaterials.isEmpty
                ? 'Create Draft'
                : 'Create Draft (${selectedMaterials.length})',
          ),
        ),
      ],
    );
  }
}
