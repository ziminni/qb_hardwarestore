import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

/// Editable draft state for one row in the Price Table.
class _PriceRowDraft {
  _PriceRowDraft({
    required this.unitId,
    required double price,
    required this.originalCreditKind,
    required this.originalCreditValue,
  }) : originalPrice = price,
       priceController = TextEditingController(text: price.toStringAsFixed(2)),
       creditKind = originalCreditKind,
       creditValueController = TextEditingController(
         text: originalCreditKind == 'NONE'
             ? ''
             : originalCreditValue.toStringAsFixed(2),
       );

  final int unitId;
  double originalPrice;
  String originalCreditKind;
  double originalCreditValue;

  final TextEditingController priceController;
  String creditKind;
  final TextEditingController creditValueController;
  String? error;
  bool saving = false;

  double? get parsedPrice =>
      double.tryParse(priceController.text.trim().replaceAll(',', ''));

  double? get parsedCreditValue => creditKind == 'NONE'
      ? 0
      : double.tryParse(creditValueController.text.trim().replaceAll(',', ''));

  double? get computedUtangPrice {
    final cash = parsedPrice;
    final val = parsedCreditValue;
    if (cash == null || cash < 0 || val == null || val < 0) return null;
    return switch (creditKind) {
      'AMOUNT' when val > 0 => cash + val,
      'PERCENT' when val > 0 => cash * (1 + val / 100),
      _ => null,
    };
  }

  bool get isDirty {
    final price = parsedPrice;
    final creditVal = parsedCreditValue;
    final priceChanged =
        price == null || (price - originalPrice).abs() > 0.001;
    final kindChanged = creditKind != originalCreditKind;
    final valChanged =
        creditKind != 'NONE' &&
        (creditVal == null || (creditVal - originalCreditValue).abs() > 0.001);
    return priceChanged || kindChanged || valChanged;
  }

  String? validate() {
    final price = parsedPrice;
    if (price == null || !price.isFinite) return 'Enter a valid price.';
    if (price < 0) return 'Price cannot be negative.';
    if (creditKind != 'NONE') {
      final val = parsedCreditValue;
      if (val == null || !val.isFinite) return 'Enter utang markup.';
      if (val < 0) return 'Markup cannot be negative.';
      if (creditKind == 'PERCENT' && val > 1000) return 'At most 1000%.';
    }
    return null;
  }

  void syncFromServer(VariantUom unit) {
    originalPrice = unit.defaultSellingPrice;
    originalCreditKind = unit.creditMarkupKind;
    originalCreditValue = unit.creditMarkupValue;
    priceController.text = unit.defaultSellingPrice.toStringAsFixed(2);
    creditKind = unit.creditMarkupKind;
    creditValueController.text = unit.creditMarkupKind == 'NONE'
        ? ''
        : unit.creditMarkupValue.toStringAsFixed(2);
    error = null;
  }

  void reset() {
    priceController.text = originalPrice.toStringAsFixed(2);
    creditKind = originalCreditKind;
    creditValueController.text = originalCreditKind == 'NONE'
        ? ''
        : originalCreditValue.toStringAsFixed(2);
    error = null;
  }

  void dispose() {
    priceController.dispose();
    creditValueController.dispose();
  }
}

class _PriceTableRow {
  const _PriceTableRow({
    required this.product,
    required this.variant,
    required this.unit,
    required this.latestCost,
  });

  final Product product;
  final ProductVariant variant;
  final VariantUom unit;
  final double? latestCost;

  bool get isBase =>
      unit.uomId == variant.baseUomId && unit.conversionFactor == 1;
}

/// Full catalogue Price Table for viewing and modifying cash selling prices and
/// Utang markups across every active product, variant, and selling unit.
class PriceTableDialog extends StatefulWidget {
  const PriceTableDialog({super.key});

  @override
  State<PriceTableDialog> createState() => _PriceTableDialogState();
}

class _PriceTableDialogState extends State<PriceTableDialog> {
  static final _decimalFormatter = FilteringTextInputFormatter.allow(
    RegExp(r'^-?\d*\.?\d{0,2}'),
  );

  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final Map<int, _PriceRowDraft> _drafts = {};

  String _searchQuery = '';
  String? _selectedCategory;
  bool _modifiedOnly = false;
  bool _savingAll = false;
  String? _bannerError;
  String? _bannerSuccess;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    for (final draft in _drafts.values) {
      draft.dispose();
    }
    super.dispose();
  }

  List<_PriceTableRow> _buildRows(InventoryViewmodel inventory) {
    final rows = <_PriceTableRow>[];
    for (final product in inventory.products) {
      if (!product.isActive) continue;
      for (final variant in product.variants) {
        if (!variant.isActive) continue;
        final cost = inventory.costFor(variant.id);
        for (final unit in variant.sellingUoms) {
          rows.add(
            _PriceTableRow(
              product: product,
              variant: variant,
              unit: unit,
              latestCost: cost,
            ),
          );
        }
      }
    }
    rows.sort((a, b) {
      final byName = a.product.baseName.toLowerCase().compareTo(
        b.product.baseName.toLowerCase(),
      );
      if (byName != 0) return byName;
      final byVar = a.variant.variantName.toLowerCase().compareTo(
        b.variant.variantName.toLowerCase(),
      );
      if (byVar != 0) return byVar;
      return a.unit.uomCode.toLowerCase().compareTo(
        b.unit.uomCode.toLowerCase(),
      );
    });
    return rows;
  }

  _PriceRowDraft _draftFor(VariantUom unit) {
    final existing = _drafts[unit.id];
    if (existing != null) {
      if (!existing.isDirty &&
          ((existing.originalPrice - unit.defaultSellingPrice).abs() > 0.001 ||
              existing.originalCreditKind != unit.creditMarkupKind ||
              (existing.originalCreditValue - unit.creditMarkupValue).abs() >
                  0.001)) {
        existing.syncFromServer(unit);
      }
      return existing;
    }
    final created = _PriceRowDraft(
      unitId: unit.id,
      price: unit.defaultSellingPrice,
      originalCreditKind: unit.creditMarkupKind,
      originalCreditValue: unit.creditMarkupValue,
    );
    _drafts[unit.id] = created;
    return created;
  }

  List<_PriceTableRow> _filterRows(List<_PriceTableRow> allRows) {
    final q = _searchQuery.trim().toLowerCase();
    return allRows
        .where((row) {
          if (_selectedCategory != null &&
              row.product.categoryName != _selectedCategory) {
            return false;
          }
          if (_modifiedOnly && !_draftFor(row.unit).isDirty) {
            return false;
          }
          if (q.isEmpty) return true;
          return row.product.baseName.toLowerCase().contains(q) ||
              row.product.categoryName.toLowerCase().contains(q) ||
              row.product.brandName.toLowerCase().contains(q) ||
              row.variant.variantName.toLowerCase().contains(q) ||
              row.variant.sku.toLowerCase().contains(q) ||
              row.unit.uomCode.toLowerCase().contains(q) ||
              row.unit.uomName.toLowerCase().contains(q) ||
              row.unit.barcodeQr.toLowerCase().contains(q);
        })
        .toList(growable: false);
  }

  List<_PriceTableRow> _dirtyRows(List<_PriceTableRow> allRows) => [
    for (final row in allRows)
      if (_draftFor(row.unit).isDirty) row,
  ];

  Future<void> _saveRow(_PriceTableRow row) async {
    final draft = _draftFor(row.unit);
    final validation = draft.validate();
    if (validation != null) {
      setState(() {
        draft.error = validation;
        _bannerSuccess = null;
      });
      return;
    }
    setState(() {
      draft.saving = true;
      draft.error = null;
      _bannerError = null;
      _bannerSuccess = null;
    });
    final inventory = context.read<InventoryViewmodel>();
    final err = await inventory.updateSellingUnitPrice(
      unitId: row.unit.id,
      sellingPrice: draft.parsedPrice!,
      creditMarkupKind: draft.creditKind,
      creditMarkupValue: draft.parsedCreditValue ?? 0,
    );
    if (!mounted) return;
    setState(() {
      draft.saving = false;
      if (err != null) {
        draft.error = err;
      } else {
        final refreshed = _findUnit(inventory, row.unit.id);
        if (refreshed != null) {
          draft.syncFromServer(refreshed);
        } else {
          draft.originalPrice = draft.parsedPrice!;
          draft.originalCreditKind = draft.creditKind;
          draft.originalCreditValue = draft.parsedCreditValue ?? 0;
        }
        _bannerSuccess =
            'Updated ${row.product.baseName} · ${row.variant.variantName} (${row.unit.uomCode}).';
      }
    });
  }

  Future<void> _saveAll(List<_PriceTableRow> allRows) async {
    final dirty = _dirtyRows(allRows);
    if (dirty.isEmpty) return;

    var hasInvalid = false;
    final batch =
        <
          ({
            int unitId,
            double sellingPrice,
            String creditMarkupKind,
            double creditMarkupValue,
          })
        >[];
    for (final row in dirty) {
      final draft = _draftFor(row.unit);
      final err = draft.validate();
      if (err != null) {
        draft.error = err;
        hasInvalid = true;
      } else {
        draft.error = null;
        batch.add((
          unitId: row.unit.id,
          sellingPrice: draft.parsedPrice!,
          creditMarkupKind: draft.creditKind,
          creditMarkupValue: draft.parsedCreditValue ?? 0,
        ));
      }
    }
    if (hasInvalid) {
      setState(() {
        _bannerError = 'Fix the highlighted price errors before saving all.';
        _bannerSuccess = null;
      });
      return;
    }

    setState(() {
      _savingAll = true;
      _bannerError = null;
      _bannerSuccess = null;
      for (final row in dirty) {
        _draftFor(row.unit).saving = true;
      }
    });

    final inventory = context.read<InventoryViewmodel>();
    final errors = await inventory.updateSellingUnitPrices(batch);
    if (!mounted) return;

    var savedCount = 0;
    setState(() {
      _savingAll = false;
      for (final row in dirty) {
        final draft = _draftFor(row.unit);
        draft.saving = false;
        final err = errors[row.unit.id];
        if (err != null) {
          draft.error = err;
        } else {
          savedCount++;
          final refreshed = _findUnit(inventory, row.unit.id);
          if (refreshed != null) {
            draft.syncFromServer(refreshed);
          } else {
            draft.originalPrice = draft.parsedPrice!;
            draft.originalCreditKind = draft.creditKind;
            draft.originalCreditValue = draft.parsedCreditValue ?? 0;
          }
        }
      }
      if (errors.isNotEmpty) {
        _bannerError =
            'Saved $savedCount price${savedCount == 1 ? '' : 's'}; '
            '${errors.length} could not be saved.';
      } else {
        _bannerSuccess =
            'Saved $savedCount selling price${savedCount == 1 ? '' : 's'}.';
      }
    });
  }

  VariantUom? _findUnit(InventoryViewmodel inventory, int unitId) {
    for (final product in inventory.products) {
      for (final variant in product.variants) {
        for (final unit in variant.sellingUoms) {
          if (unit.id == unitId) return unit;
        }
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    final allRows = _buildRows(inventory);
    // Ensure drafts exist for all current rows so dirty count is accurate.
    for (final row in allRows) {
      _draftFor(row.unit);
    }
    final categories =
        allRows
            .map((r) => r.product.categoryName)
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    if (_selectedCategory != null && !categories.contains(_selectedCategory)) {
      _selectedCategory = null;
    }
    final visibleRows = _filterRows(allRows);
    final dirtyCount = _dirtyRows(allRows).length;

    return AppDialog(
      icon: Icons.price_change_outlined,
      title: 'Selling Price Table',
      subtitle:
          'View and modify cash selling prices and Utang markups across all products, variants, and units.',
      width: 1140,
      scrollable: false,
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.72,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_bannerError != null) ...[
              ErrorBanner(message: _bannerError!),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (_bannerSuccess != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.small),
                  border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      size: 18,
                      color: AppColors.success,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _bannerSuccess!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            LayoutBuilder(
              builder: (context, constraints) {
                final searchField = TextField(
                  key: const ValueKey('price-table-search'),
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search product, variant, unit, or barcode',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            icon: const Icon(Icons.close, size: 18),
                          ),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _searchQuery = v),
                );
                final categoryDropdown = DropdownButtonFormField<String?>(
                  key: ValueKey('price-table-cat-$_selectedCategory'),
                  isExpanded: true,
                  initialValue: _selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All categories'),
                    ),
                    for (final c in categories)
                      DropdownMenuItem(
                        value: c,
                        child: Text(c, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) => setState(() => _selectedCategory = v),
                );
                final modifiedChip = FilterChip(
                  key: const ValueKey('price-table-modified-filter'),
                  selected: _modifiedOnly,
                  label: Text('Modified ($dirtyCount)'),
                  onSelected: (v) => setState(() => _modifiedOnly = v),
                );

                if (constraints.maxWidth >= 700) {
                  return Row(
                    children: [
                      Expanded(flex: 3, child: searchField),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(flex: 2, child: categoryDropdown),
                      const SizedBox(width: AppSpacing.md),
                      modifiedChip,
                    ],
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    searchField,
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(child: categoryDropdown),
                        const SizedBox(width: AppSpacing.sm),
                        modifiedChip,
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Showing ${visibleRows.length} of ${allRows.length} '
                    'selling ${allRows.length == 1 ? 'price' : 'prices'}'
                    '${dirtyCount > 0 ? ' · $dirtyCount unsaved' : ''}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (dirtyCount > 0)
                  TextButton(
                    onPressed: _savingAll
                        ? null
                        : () => setState(() {
                            for (final row in allRows) {
                              _draftFor(row.unit).reset();
                            }
                            _bannerError = null;
                          }),
                    child: const Text('Discard unsaved'),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: visibleRows.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Text(
                          allRows.isEmpty
                              ? 'No selling units in the catalogue yet.'
                              : 'No selling prices match the current filter.',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 760;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (wide) _tableHeader(context),
                            Expanded(
                              child: Scrollbar(
                                controller: _scrollController,
                                thumbVisibility: true,
                                child: ListView.separated(
                                  controller: _scrollController,
                                  itemCount: visibleRows.length,
                                  separatorBuilder: (_, _) =>
                                      const Divider(height: 1),
                                  itemBuilder: (context, index) {
                                    final row = visibleRows[index];
                                    return wide
                                        ? _wideRow(context, row)
                                        : _narrowCard(context, row);
                                  },
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _savingAll ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton.icon(
          key: const ValueKey('price-table-save-all'),
          onPressed: _savingAll || dirtyCount == 0
              ? null
              : () => _saveAll(allRows),
          icon: const Icon(Icons.save_outlined, size: 18),
          label: Text(
            _savingAll
                ? 'Saving…'
                : dirtyCount == 0
                ? 'All prices saved'
                : 'Save all changes ($dirtyCount)',
          ),
        ),
      ],
    );
  }

  Widget _tableHeader(BuildContext context) {
    const headerStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppColors.textSecondary,
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadii.small),
        ),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Expanded(flex: 3, child: Text('Product / Variant', style: headerStyle)),
          SizedBox(width: AppSpacing.sm),
          Expanded(flex: 2, child: Text('Unit & Barcode', style: headerStyle)),
          SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 84,
            child: Text('Cost', textAlign: TextAlign.right, style: headerStyle),
          ),
          SizedBox(width: AppSpacing.md),
          SizedBox(width: 140, child: Text('Selling Price', style: headerStyle)),
          SizedBox(width: AppSpacing.md),
          Expanded(flex: 3, child: Text('Utang Markup', style: headerStyle)),
          SizedBox(width: AppSpacing.sm),
          SizedBox(
            width: 124,
            child: Text(
              'Action',
              textAlign: TextAlign.right,
              style: headerStyle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _wideRow(BuildContext context, _PriceTableRow row) {
    final draft = _draftFor(row.unit);
    final dirty = draft.isDirty;
    final utangPrice = draft.computedUtangPrice;
    final unitCode = row.unit.uomCode;

    return Container(
      key: ValueKey('price-row-${row.unit.id}'),
      color: dirty ? AppColors.selected.withValues(alpha: 0.25) : null,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.product.baseName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${row.variant.variantName} · ${row.product.categoryName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          row.isBase
                              ? unitCode
                              : '$unitCode (×${formatQuantity(row.unit.conversionFactor)})',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        if (row.isBase) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Theme.of(
                                context,
                              ).colorScheme.secondaryContainer,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              'Base',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      row.unit.barcodeQr.isEmpty
                          ? 'No barcode'
                          : row.unit.barcodeQr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 84,
                child: Text(
                  row.latestCost == null ? '—' : formatPeso(row.latestCost!),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              SizedBox(
                width: 140,
                child: TextField(
                  key: ValueKey('price-input-${row.unit.id}'),
                  controller: draft.priceController,
                  enabled: !draft.saving && !_savingAll,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [_decimalFormatter],
                  onChanged: (_) => setState(() => draft.error = null),
                  onSubmitted: (_) {
                    if (draft.isDirty) _saveRow(row);
                  },
                  decoration: InputDecoration(
                    prefixText: '₱ ',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    suffixText: '/$unitCode',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    SizedBox(
                      width: 112,
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(
                          'price-utang-kind-${row.unit.id}-${draft.creditKind}',
                        ),
                        initialValue: draft.creditKind,
                        isDense: true,
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'NONE', child: Text('None')),
                          DropdownMenuItem(
                            value: 'AMOUNT',
                            child: Text('+ ₱'),
                          ),
                          DropdownMenuItem(
                            value: 'PERCENT',
                            child: Text('+ %'),
                          ),
                        ],
                        onChanged: draft.saving || _savingAll
                            ? null
                            : (v) => setState(() {
                                draft.creditKind = v ?? 'NONE';
                                draft.error = null;
                              }),
                      ),
                    ),
                    if (draft.creditKind != 'NONE') ...[
                      const SizedBox(width: AppSpacing.xs),
                      SizedBox(
                        width: 82,
                        child: TextField(
                          key: ValueKey('price-utang-val-${row.unit.id}'),
                          controller: draft.creditValueController,
                          enabled: !draft.saving && !_savingAll,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [_decimalFormatter],
                          onChanged: (_) => setState(() => draft.error = null),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            prefixText: draft.creditKind == 'AMOUNT'
                                ? '₱'
                                : null,
                            suffixText: draft.creditKind == 'PERCENT'
                                ? '%'
                                : null,
                          ),
                        ),
                      ),
                    ],
                    if (utangPrice != null) ...[
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          formatPeso(utangPrice),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              SizedBox(
                width: 124,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (dirty && !draft.saving)
                      IconButton(
                        tooltip: 'Reset row',
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: EdgeInsets.zero,
                        onPressed: _savingAll
                            ? null
                            : () => setState(draft.reset),
                        icon: const Icon(Icons.undo, size: 17),
                      ),
                    FilledButton.tonal(
                      key: ValueKey('price-save-${row.unit.id}'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(56, 34),
                      ),
                      onPressed: !dirty || draft.saving || _savingAll
                          ? null
                          : () => _saveRow(row),
                      child: Text(draft.saving ? '…' : 'Save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (draft.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                draft.error!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _narrowCard(BuildContext context, _PriceTableRow row) {
    final draft = _draftFor(row.unit);
    final dirty = draft.isDirty;
    final utangPrice = draft.computedUtangPrice;
    final unitCode = row.unit.uomCode;

    return Container(
      key: ValueKey('price-row-${row.unit.id}'),
      color: dirty ? AppColors.selected.withValues(alpha: 0.25) : null,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row.product.baseName} · ${row.variant.variantName}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${row.isBase ? '$unitCode (Base)' : '$unitCode (×${formatQuantity(row.unit.conversionFactor)})'}'
                      '${row.latestCost != null ? ' · Cost ${formatPeso(row.latestCost!)}' : ''}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                key: ValueKey('price-save-${row.unit.id}'),
                onPressed: !dirty || draft.saving || _savingAll
                    ? null
                    : () => _saveRow(row),
                child: Text(draft.saving ? '…' : 'Save'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('price-input-${row.unit.id}'),
                  controller: draft.priceController,
                  enabled: !draft.saving && !_savingAll,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [_decimalFormatter],
                  onChanged: (_) => setState(() => draft.error = null),
                  decoration: InputDecoration(
                    labelText: 'Price / $unitCode',
                    prefixText: '₱ ',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    'price-utang-kind-${row.unit.id}-${draft.creditKind}',
                  ),
                  initialValue: draft.creditKind,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Utang markup',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'NONE', child: Text('None')),
                    DropdownMenuItem(value: 'AMOUNT', child: Text('+ ₱')),
                    DropdownMenuItem(value: 'PERCENT', child: Text('+ %')),
                  ],
                  onChanged: draft.saving || _savingAll
                      ? null
                      : (v) => setState(() {
                          draft.creditKind = v ?? 'NONE';
                          draft.error = null;
                        }),
                ),
              ),
              if (draft.creditKind != 'NONE') ...[
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 90,
                  child: TextField(
                    key: ValueKey('price-utang-val-${row.unit.id}'),
                    controller: draft.creditValueController,
                    enabled: !draft.saving && !_savingAll,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_decimalFormatter],
                    onChanged: (_) => setState(() => draft.error = null),
                    decoration: InputDecoration(
                      labelText: draft.creditKind == 'PERCENT' ? '%' : '₱',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (utangPrice != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Utang price: ${formatPeso(utangPrice)} / $unitCode',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          if (draft.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                draft.error!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Focused dialog to edit one selling unit's cash selling price and Utang
/// markup directly from Product Details.
class EditSellingPriceDialog extends StatefulWidget {
  const EditSellingPriceDialog({
    super.key,
    required this.productName,
    required this.variantName,
    required this.unit,
    required this.onSubmit,
  });

  final String productName;
  final String variantName;
  final VariantUom unit;
  final Future<String?> Function({
    required double sellingPrice,
    required String creditMarkupKind,
    required double creditMarkupValue,
  })
  onSubmit;

  @override
  State<EditSellingPriceDialog> createState() => _EditSellingPriceDialogState();
}

class _EditSellingPriceDialogState extends State<EditSellingPriceDialog> {
  static final _decimalFormatter = FilteringTextInputFormatter.allow(
    RegExp(r'^-?\d*\.?\d{0,2}'),
  );

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _priceController = TextEditingController(
    text: widget.unit.defaultSellingPrice.toStringAsFixed(2),
  );
  late String _creditKind = widget.unit.creditMarkupKind;
  late final TextEditingController _creditValueController =
      TextEditingController(
        text: widget.unit.creditMarkupKind == 'NONE'
            ? ''
            : widget.unit.creditMarkupValue.toStringAsFixed(2),
      );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _priceController.dispose();
    _creditValueController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final price = double.parse(_priceController.text.trim().replaceAll(',', ''));
    final creditVal = _creditKind == 'NONE'
        ? 0.0
        : double.parse(_creditValueController.text.trim().replaceAll(',', ''));
    final err = await widget.onSubmit(
      sellingPrice: price,
      creditMarkupKind: _creditKind,
      creditMarkupValue: creditVal,
    );
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _error = err;
        _saving = false;
      });
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final code = widget.unit.uomCode;
    return AppDialog(
      icon: Icons.sell_outlined,
      title: 'Edit selling price',
      subtitle: '${widget.productName} · ${widget.variantName} · $code',
      width: 460,
      content: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_error != null) ...[
              ErrorBanner(message: _error!),
              const SizedBox(height: AppSpacing.md),
            ],
            TextFormField(
              key: const ValueKey('edit-unit-price-field'),
              controller: _priceController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [_decimalFormatter],
              decoration: InputDecoration(
                labelText: 'Selling price per $code',
                prefixText: '₱ ',
              ),
              validator: (raw) {
                final v = double.tryParse((raw ?? '').trim().replaceAll(',', ''));
                if (v == null || !v.isFinite) return 'Enter a valid price.';
                if (v < 0) return 'Price cannot be negative.';
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    key: const ValueKey('edit-unit-credit-kind'),
                    initialValue: _creditKind,
                    decoration: const InputDecoration(
                      labelText: 'Utang markup',
                      helperText: 'Cash price is unchanged.',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'NONE', child: Text('None')),
                      DropdownMenuItem(
                        value: 'AMOUNT',
                        child: Text('Peso amount'),
                      ),
                      DropdownMenuItem(
                        value: 'PERCENT',
                        child: Text('Percent'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _creditKind = v ?? 'NONE'),
                  ),
                ),
                if (_creditKind != 'NONE') ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      key: const ValueKey('edit-unit-credit-value'),
                      controller: _creditValueController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [_decimalFormatter],
                      decoration: InputDecoration(
                        labelText: _creditKind == 'PERCENT'
                            ? 'Percent'
                            : 'Peso amount',
                        prefixText: _creditKind == 'AMOUNT' ? '₱ ' : null,
                        suffixText: _creditKind == 'PERCENT' ? '%' : null,
                      ),
                      validator: (raw) {
                        final v = double.tryParse(
                          (raw ?? '').trim().replaceAll(',', ''),
                        );
                        if (v == null || !v.isFinite || v < 0) {
                          return 'Enter 0 or more.';
                        }
                        if (_creditKind == 'PERCENT' && v > 1000) {
                          return 'At most 1000%.';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('edit-unit-price-save'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Saving…' : 'Save price'),
        ),
      ],
    );
  }
}
