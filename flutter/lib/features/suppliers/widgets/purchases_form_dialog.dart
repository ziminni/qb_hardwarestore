import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/sale_discount.dart' show roundMoney;
import 'package:client/data/models/purchase_draft.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/data/models/variant_uom.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:client/shared/widgets/app_dialog.dart';
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
    required this.baseCost,
    this.unit,
  });

  final ProductVariant variant;

  /// The landed cost per BASE unit (decision 08). The per-unit prefill is this
  /// times the selected unit's factor, so switching to BAG does not silently
  /// turn a per-kilo price into a per-bag one.
  final double baseCost;

  /// The selling unit this line is counted in; null when the variant's own
  /// catalogue lists none, and then the line goes to the server without a unit
  /// (base unit, the older meaning).
  VariantUom? unit;

  final TextEditingController quantity;
  final TextEditingController unitCost;

  String get unitCode => unit?.uomCode ?? variant.baseUomCode;
  double get factor => unit?.conversionFactor ?? 1;
  bool get isWhole => unit?.uomIsWhole ?? false;

  /// The prefill this line's cost box starts with, given its current unit.
  String get prefilledCost => (baseCost * factor).toStringAsFixed(2);

  void dispose() {
    quantity.dispose();
    unitCost.dispose();
  }
}

class _PurchasesFormDialogState extends State<PurchasesFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _notesController = TextEditingController();

  /// Pesos off the whole order (Phase 5 B2). Blank means nothing off.
  final _discountController = TextEditingController();

  /// Whether the line prices already contain VAT. The server's own default.
  bool _vatInclusive = true;
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
    _discountController.dispose();
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
    final baseCost = widget.costFor(variant.id);
    // The default is the variant's REAL base row (`uomId == baseUomId` at factor
    // 1), never the first selling unit: a packaged variant lists its BAG before
    // its KG, and taking the first row would count the order in bags.
    final unit = variant.baseSellingUnit;
    _lines.add(
      _PurchaseOrderLineForm(
        variant: variant,
        baseCost: baseCost,
        unit: unit,
        quantity: TextEditingController(
          text: (quantity ?? 1).toStringAsFixed(0),
        ),
        unitCost: TextEditingController(
          text: (baseCost * (unit?.conversionFactor ?? 1)).toStringAsFixed(2),
        ),
      ),
    );
  }

  /// Switches a line to [unit] without reinterpreting what was typed.
  ///
  /// The cost box follows the unit only while it still holds its untouched
  /// prefill; a typed price and a typed quantity are the user's numbers and stay
  /// as written, under the explicit `Cost per <unit>` label.
  void _changeUnit(_PurchaseOrderLineForm line, VariantUom unit) {
    setState(() {
      final untouched = line.unitCost.text.trim() == line.prefilledCost;
      line.unit = unit;
      if (untouched) line.unitCost.text = line.prefilledCost;
    });
  }

  /// `10 BAG = 250 KG` for the typed quantity, or null when the line is counted
  /// in base units already.
  String? _conversionText(_PurchaseOrderLineForm line) {
    final qty = double.tryParse(line.quantity.text.trim());
    if (line.factor == 1 || qty == null || qty <= 0) return null;
    return '${formatQuantity(qty)} ${line.unitCode} = '
        '${formatQuantity(qty * line.factor)} ${line.variant.baseUomCode}';
  }

  /// The discount as typed, or 0 when the box is blank.
  double get _discount => double.tryParse(_discountController.text.trim()) ?? 0;

  /// What the order comes to after the discount. The SERVER's figures (which
  /// include VAT) win once the order exists; this is the before-you-save view.
  double get _netTotal => roundMoney(_orderTotal - _discount);

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
          variantUomId: line.unit?.id,
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
          discountAmount: _discount,
          vatInclusive: _vatInclusive,
          lines: lines,
        ),
        place: place,
      ),
    );
  }

  Future<void> _pickExpectedDelivery() async {
    final now = appClock.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expectedDelivery ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      // The "today" ring follows the app's clock, not the framework's own
      // `DateTime.now()`.
      currentDate: now,
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
    // Under this window width two panes side by side leave each field too narrow
    // to show its own label, so they stack instead. Read from the window, not
    // from a layout callback: the dialog asks for intrinsic sizes while it
    // centres itself, and a LayoutBuilder cannot answer those.
    final stacked = MediaQuery.sizeOf(context).width < _sideBySideBreakpoint;

    return AppDialog(
      icon: Icons.local_shipping_outlined,
      title: 'New purchase order',
      subtitle: 'Pick materials on the left, then set quantity and cost.',
      width: 880,
      // The form sizes itself: each list pane has a viewport of its own and the
      // dialog grows around them, so a short window SCROLLS the form instead of
      // squeezing the two panes (the old `height - 190` formula did the reverse:
      // the same content was 620 px tall on a tall window and 400 on a short
      // one, whatever the panes needed).
      scrollable: true,
      content: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _headerRow(theme, colors, activeSuppliers),
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
            if (stacked) ...[
              SizedBox(
                height: _stackedPaneHeight,
                child: _cataloguePane(theme, filteredMaterials),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                height: _stackedPaneHeight,
                child: _linesPane(theme, colors),
              ),
            ] else
              SizedBox(
                height: _paneHeight,
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
            const SizedBox(height: AppSpacing.lg),
            _moneyBlock(theme, colors),
          ],
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

  /// Window width under which the two panes stack: below it a pane is too
  /// narrow for a labelled field and a price on one line.
  static const double _sideBySideBreakpoint = 900;

  /// Viewport height of each list pane. A list needs a bounded height to scroll
  /// itself; these are the panes' own size, not the window's, so the dialog
  /// keeps the same shape on every screen and scrolls when the window is short.
  static const double _paneHeight = 230;
  // 200 rather than 220: on a 760 wide window the dialog is capped at 90% of the
  // window height, and 40 px less here is the difference between the Notes field
  // being visible and being below the fold.
  static const double _stackedPaneHeight = 200;

  Widget _headerRow(
    ThemeData theme,
    ColorScheme colors,
    List<Supplier> activeSuppliers,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
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
              style: theme.textTheme.bodySmall?.copyWith(color: colors.error),
            ),
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
                                Expanded(child: _unitPicker(line)),
                                const SizedBox(width: AppSpacing.md),
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
                                      suffixText: line.unitCode,
                                      isDense: true,
                                    ),
                                    validator: (value) =>
                                        _quantityError(line, value),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            TextFormField(
                              key: ValueKey('po-cost-${line.variant.id}'),
                              controller: line.unitCost,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                // The unit is IN the label: a per-kilo landed
                                // cost must not read as a per-bag price after a
                                // unit change.
                                labelText: 'Cost per ${line.unitCode}',
                                helperText: _conversionText(line),
                                helperMaxLines: 2,
                                prefixText: '₱ ',
                                isDense: true,
                              ),
                              validator: _nonNegativeNumber,
                              onChanged: (_) => setState(() {}),
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
                  formatPeso(_netTotal),
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

  /// The selling-unit picker for one line, from the variant's OWN catalogue.
  ///
  /// A variant with no selling units listed has no unit to name, so the line
  /// says which unit the server will count it in and sends no id (base unit).
  Widget _unitPicker(_PurchaseOrderLineForm line) {
    final units = line.variant.sellingUoms;
    if (units.isEmpty) {
      return InputDecorator(
        decoration: const InputDecoration(labelText: 'Unit', isDense: true),
        child: Text(line.unitCode),
      );
    }
    return DropdownButtonFormField<int>(
      key: ValueKey('po-unit-${line.variant.id}'),
      isExpanded: true,
      initialValue: line.unit?.id,
      decoration: const InputDecoration(labelText: 'Unit', isDense: true),
      items: [
        for (final unit in units)
          DropdownMenuItem(
            value: unit.id,
            child: Text(unit.uomCode, overflow: TextOverflow.ellipsis),
          ),
      ],
      // No base row in the catalogue means no honest default: the user picks.
      validator: (value) => value == null ? 'Choose a unit.' : null,
      onChanged: (id) {
        if (id == null) return;
        for (final unit in units) {
          if (unit.id == id) {
            _changeUnit(line, unit);
            return;
          }
        }
      },
    );
  }

  /// The typed quantity, checked against the SELECTED unit: a whole unit takes
  /// whole counts, a measured one takes at most two decimals (the server's own
  /// quantity precision).
  static String? _quantityError(_PurchaseOrderLineForm line, String? value) {
    final text = value?.trim() ?? '';
    final parsed = double.tryParse(text);
    if (parsed == null || parsed <= 0) return 'Above 0';
    if (line.isWhole && parsed != parsed.roundToDouble()) {
      return 'Whole ${line.unitCode} only';
    }
    if (!line.isWhole) {
      final dot = text.indexOf('.');
      if (dot >= 0 && text.length - dot - 1 > 2) return 'At most 2 decimals';
    }
    return null;
  }

  /// The header money of the order: the discount, whether the prices include
  /// VAT, and the before-VAT preview (Phase 5 B2).
  ///
  /// Both controls are editable here because a new order is always a DRAFT; the
  /// server locks them once it is placed (`PO_LOCKED`) and this dialog only ever
  /// creates. The VAT split itself is not previewed: the rate is the shop's,
  /// taken from `store-settings` when the order is created.
  Widget _moneyBlock(ThemeData theme, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const DialogSectionLabel('Order money'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                key: const ValueKey('po-discount'),
                controller: _discountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Discount',
                  prefixText: '₱ ',
                  helperText: 'Pesos off the whole order. Optional.',
                  isDense: true,
                ),
                validator: _discountError,
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              // A bare Switch, not a SwitchListTile: a ListTile needs a Material
              // of its own inside this dialog body.
              child: Row(
                children: [
                  Switch(
                    key: const ValueKey('po-vat-inclusive'),
                    value: _vatInclusive,
                    onChanged: (value) => setState(() => _vatInclusive = value),
                  ),
                  const Expanded(
                    child: Text(
                      'Prices include VAT',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.lg,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _previewFigure('Gross', _orderTotal),
            _previewFigure('Discount', _discount),
            _previewFigure('Net', _netTotal),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'VAT is worked out by the server from the shop rate.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  /// One preview figure: a small label over the money.
  Widget _previewFigure(String label, double amount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        Text(
          formatPeso(amount),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  /// A discount is capped by the gross: the server refuses more with
  /// `INVALID_PO`, and finding that out before the round trip saves a draft
  /// nobody meant to save.
  String? _discountError(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final parsed = double.tryParse(text);
    if (parsed == null) return 'Enter an amount.';
    if (parsed < 0) return 'A discount cannot be negative.';
    if (roundMoney(parsed) > roundMoney(_orderTotal)) {
      return 'A discount cannot be more than the order total of '
          '${formatPeso(_orderTotal)}.';
    }
    return null;
  }

  static String? _nonNegativeNumber(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null || parsed < 0) return 'Not negative';
    return null;
  }
}
