import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/product_writes.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Callback for creating a custom Unit of Measure inline without leaving a
/// product / variant / selling-unit dialog.
typedef InlineUnitCreator =
    Future<({UnitOfMeasure? unit, String? error})> Function({
      required String code,
      required String name,
    });

/// Opens a compact dialog to create a custom Unit of Measure (e.g. PC, BOX,
/// SACK, TRAY, DOZEN) inline and returns the created unit, or null if cancelled.
Future<UnitOfMeasure?> showCreateCustomUnitDialog(
  BuildContext context,
  InlineUnitCreator onCreateUnit,
) {
  return showDialog<UnitOfMeasure>(
    context: context,
    builder: (_) => _CreateCustomUnitDialog(onCreateUnit: onCreateUnit),
  );
}

class _CreateCustomUnitDialog extends StatefulWidget {
  const _CreateCustomUnitDialog({required this.onCreateUnit});

  final InlineUnitCreator onCreateUnit;

  @override
  State<_CreateCustomUnitDialog> createState() =>
      _CreateCustomUnitDialogState();
}

class _CreateCustomUnitDialogState extends State<_CreateCustomUnitDialog> {
  final _codeController = TextEditingController();
  final _nameController = TextEditingController();
  String? _errorText;
  bool _saving = false;

  @override
  void dispose() {
    _codeController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _errorText = null;
    });
    final res = await widget.onCreateUnit(
      code: _codeController.text,
      name: _nameController.text,
    );
    if (!mounted) return;
    if (res.unit != null) {
      Navigator.of(context).pop(res.unit);
    } else {
      setState(() {
        _saving = false;
        _errorText = res.error ?? 'Could not create unit.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New custom unit'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('custom-uom-code'),
              controller: _codeController,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Unit code',
                hintText: 'e.g. PC, BOX, SACK, TRAY, KG',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              key: const ValueKey('custom-uom-name'),
              controller: _nameController,
              decoration: InputDecoration(
                labelText: 'Unit name',
                hintText: 'e.g. Piece, Box, Sack, Tray, Kilogram',
                errorText: _errorText,
              ),
              onSubmitted: (_) => _submit(),
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
          key: const ValueKey('custom-uom-create'),
          onPressed: _saving ? null : _submit,
          child: Text(_saving ? 'Saving…' : 'Create'),
        ),
      ],
    );
  }
}

/// One extra selling unit being typed: "1 Bag = 40 kg at ₱270", or a sub-unit
/// like "1 PC = 0.05 BOX (20 PC = 1 BOX) at ₱30".
///
/// A row owns its controllers and its picked unit id, so removing the row in the
/// middle of a list cannot shuffle another row's typed text. Shared by the Edit
/// product form and the details dialog's "Add selling unit" (Phase 1d Task 9).
class SellingUnitDraft {
  final factor = TextEditingController();
  final price = TextEditingController();
  final code = TextEditingController();
  final creditMarkupValue = TextEditingController();
  int? uomId;
  String creditMarkupKind = 'NONE';

  double get resolvedCreditValue => creditMarkupKind == 'NONE'
      ? 0
      : (double.tryParse(creditMarkupValue.text.trim().replaceAll(',', '')) ??
            0);

  void dispose() {
    factor.dispose();
    price.dispose();
    code.dispose();
    creditMarkupValue.dispose();
  }
}

/// How many decimals a typed number has: `40` is 0, `40.25` is 2.
int sellingUnitDecimalPlaces(String text) {
  final dot = text.indexOf('.');
  return dot < 0 ? 0 : text.length - dot - 1;
}

/// The server's `INVALID_SELLING_UNIT` rules, checked before the POST.
String? sellingUnitFactorError(String? raw, {required String baseCode}) {
  final text = raw?.trim() ?? '';
  final value = double.tryParse(text);
  if (value == null) return 'Enter how many $baseCode this unit holds.';
  if (value < 0.01) return 'A selling unit holds at least 0.01 $baseCode.';
  if (value == 1) return 'A unit of 1 $baseCode is the base unit.';
  if (sellingUnitDecimalPlaces(text) > 2) return 'Use at most 2 decimals.';
  return null;
}

/// One unit per variant, and never the base unit again.
String? sellingUnitUnitError(
  int? value, {
  required int? baseUomId,
  required Iterable<int?> usedUomIds,
}) {
  if (value == null) return 'Choose a selling unit.';
  if (value == baseUomId) return 'This unit is already used.';
  for (final id in usedUomIds) {
    if (id == value) return 'This unit is already used.';
  }
  return null;
}

String? sellingUnitPriceError(String? raw) {
  final value = double.tryParse(raw?.trim() ?? '');
  if (value == null) return 'Enter a price.';
  if (value < 0) return 'The price cannot be negative.';
  return null;
}

/// How the clerk enters the conversion relative to the variant's base unit.
enum _ConversionMode {
  /// Direct entry: "1 [selling unit] = ? [base unit]" (e.g. 1 BAG = 40 KG).
  direct,

  /// Sub-unit entry: "1 [base unit] = ? [selling unit]" (e.g. 1 BOX = 20 PC
  /// → automatically calculates 0.05 BOX per PC).
  subUnit,
}

/// The fields of ONE extra selling unit: base unit reference banner, selling
/// unit picker, direct/sub-unit conversion input, dynamic per-unit price,
/// optional utang markup, factory barcode, and live conversion preview.
///
/// [keyPrefix] keeps the widget tests' finders stable and distinct when two
/// dialogs use the same fields (`row` in the product form, `add` in details).
class SellingUnitFields extends StatefulWidget {
  const SellingUnitFields({
    super.key,
    required this.draft,
    required this.index,
    required this.keyPrefix,
    required this.baseCode,
    required this.units,
    this.basePrice,
    this.onCreateUnit,
    this.validateUnit,
    this.validateFactor,
    this.validatePrice,
    this.onRemove,
    this.autofocus = false,
  });

  final SellingUnitDraft draft;
  final int index;
  final String keyPrefix;
  final String baseCode;
  final List<UnitOfMeasure> units;

  /// Optional base-unit cash selling price shown in the reference banner and
  /// live comparison preview (e.g. "Base unit: BOX · ₱500.00 / BOX").
  final double? basePrice;

  /// Optional inline "+ New" custom unit creator shown next to the dropdown.
  final InlineUnitCreator? onCreateUnit;
  final String? Function(int?)? validateUnit;
  final String? Function(String?)? validateFactor;
  final String? Function(String?)? validatePrice;
  final VoidCallback? onRemove;
  final bool autofocus;

  @override
  State<SellingUnitFields> createState() => _SellingUnitFieldsState();
}

class _SellingUnitFieldsState extends State<SellingUnitFields> {
  static final _decimalFormatter = FilteringTextInputFormatter.allow(
    RegExp(r'^-?\d*\.?\d{0,2}'),
  );

  final _unitsPerBaseController = TextEditingController();
  late List<UnitOfMeasure> _units = List<UnitOfMeasure>.of(widget.units);
  _ConversionMode _mode = _ConversionMode.direct;
  String? _subUnitHintError;

  SellingUnitDraft get draft => widget.draft;
  int get index => widget.index;
  String get keyPrefix => widget.keyPrefix;
  String get baseCode => widget.baseCode;
  List<UnitOfMeasure> get units => _units;

  @override
  void didUpdateWidget(covariant SellingUnitFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.units != widget.units) {
      _units = List<UnitOfMeasure>.of(widget.units);
    }
  }

  Future<void> _createCustomUnit() async {
    final creator = widget.onCreateUnit;
    if (creator == null) return;
    final created = await showCreateCustomUnitDialog(context, creator);
    if (!mounted || created == null) return;
    setState(() {
      if (!_units.any((u) => u.id == created.id)) {
        _units.add(created);
      }
      draft.uomId = created.id;
    });
  }

  String get _selectedCode {
    for (final unit in units) {
      if (unit.id == draft.uomId) return unit.code;
    }
    return 'unit';
  }

  @override
  void dispose() {
    _unitsPerBaseController.dispose();
    super.dispose();
  }

  void _onUnitsPerBaseChanged(String raw) {
    final text = raw.trim();
    if (text.isEmpty) {
      setState(() => _subUnitHintError = null);
      draft.factor.text = '';
      return;
    }
    final count = double.tryParse(text);
    if (count == null || count <= 1) {
      setState(() {
        _subUnitHintError = 'Enter a number greater than 1 (e.g. 10, 20, 100).';
      });
      draft.factor.text = '';
      return;
    }
    final computed = 1 / count;
    if (computed < 0.01) {
      setState(() {
        _subUnitHintError =
            'Max 100 $_selectedCode per 1 $baseCode (min factor is 0.01 $baseCode).';
      });
      draft.factor.text = '';
      return;
    }
    final rounded = double.parse(computed.toStringAsFixed(2));
    final exactCheck = (rounded * count - 1).abs();
    setState(() {
      _subUnitHintError = exactCheck > 0.005
          ? 'Rounded to ${formatQuantity(rounded)} $baseCode per $_selectedCode '
                '(at most 2 decimals).'
          : null;
    });
    draft.factor.text = rounded.toStringAsFixed(2).replaceFirst(
      RegExp(r'\.?0+$'),
      '',
    );
  }

  void _switchMode(_ConversionMode next) {
    if (_mode == next) return;
    setState(() {
      _mode = next;
      _subUnitHintError = null;
      if (next == _ConversionMode.subUnit) {
        final current = double.tryParse(draft.factor.text.trim());
        if (current != null && current > 0 && current < 1) {
          _unitsPerBaseController.text = formatQuantity(1 / current);
        } else {
          _unitsPerBaseController.clear();
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedCode = _selectedCode;
    return Container(
      key: ValueKey('$keyPrefix-row-$index'),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.secondaryContainer.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(AppRadii.small),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.straighten_outlined, size: 16),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    widget.basePrice == null
                        ? 'Base unit: $baseCode (×1)'
                        : 'Base unit: $baseCode (×1) · '
                              '${formatPeso(widget.basePrice!)} / $baseCode',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: KeyedSubtree(
                  key: ValueKey('$keyPrefix-unit-list-${units.length}-${draft.uomId}'),
                  child: DropdownButtonFormField<int>(
                    key: ValueKey('$keyPrefix-unit-$index'),
                    isExpanded: true,
                    initialValue: draft.uomId,
                    decoration: const InputDecoration(
                      labelText: 'Unit (Box, Bag, Roll…)',
                      helperText: 'e.g. BOX, BAG, ROLL, PACK, PC',
                    ),
                    items: units
                        .map(
                          (unit) => DropdownMenuItem(
                            value: unit.id,
                            child: Text(
                              unit.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    validator: widget.validateUnit,
                    onChanged: (value) => setState(() => draft.uomId = value),
                  ),
                ),
              ),
              if (widget.onCreateUnit != null) ...[
                const SizedBox(width: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: OutlinedButton.icon(
                    key: ValueKey('$keyPrefix-new-unit-$index'),
                    onPressed: _createCustomUnit,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New'),
                  ),
                ),
              ],
              if (widget.onRemove != null)
                IconButton(
                  key: ValueKey('remove-$keyPrefix-$index'),
                  tooltip: 'Remove this unit',
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<_ConversionMode>(
            key: ValueKey('$keyPrefix-mode-$index'),
            segments: [
              ButtonSegment(
                value: _ConversionMode.direct,
                label: Text('1 $selectedCode = ? $baseCode'),
              ),
              ButtonSegment(
                value: _ConversionMode.subUnit,
                label: Text('1 $baseCode = ? $selectedCode'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (values) => _switchMode(values.first),
          ),
          const SizedBox(height: AppSpacing.md),
          if (_mode == _ConversionMode.subUnit) ...[
            TextFormField(
              key: ValueKey('$keyPrefix-subcount-$index'),
              controller: _unitsPerBaseController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [_decimalFormatter],
              onChanged: _onUnitsPerBaseChanged,
              decoration: InputDecoration(
                labelText: 'How many $selectedCode in 1 $baseCode',
                hintText: 'e.g. 20 or 100',
                suffixText: '$selectedCode / $baseCode',
                helperText:
                    _subUnitHintError ??
                    'Auto-calculates the $baseCode conversion factor below.',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextFormField(
                  key: ValueKey('$keyPrefix-factor-$index'),
                  controller: draft.factor,
                  autofocus: widget.autofocus,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [_decimalFormatter],
                  decoration: InputDecoration(
                    labelText: 'Contains how many $baseCode?',
                    hintText: _mode == _ConversionMode.subUnit
                        ? '0.05'
                        : 'e.g. 40 or 2.5',
                    suffixText: baseCode,
                  ),
                  validator: widget.validateFactor,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: TextFormField(
                  key: ValueKey('$keyPrefix-price-$index'),
                  controller: draft.price,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [_decimalFormatter],
                  decoration: const InputDecoration(
                    labelText: 'Selling price for the whole pack',
                    hintText: '0.00',
                    prefixText: '₱ ',
                  ),
                  validator: widget.validatePrice,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('$keyPrefix-credit-kind-$index'),
                  initialValue: draft.creditMarkupKind,
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
                    DropdownMenuItem(value: 'PERCENT', child: Text('Percent')),
                  ],
                  onChanged: (value) =>
                      setState(() => draft.creditMarkupKind = value ?? 'NONE'),
                ),
              ),
              if (draft.creditMarkupKind != 'NONE') ...[
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    key: ValueKey('$keyPrefix-credit-value-$index'),
                    controller: draft.creditMarkupValue,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_decimalFormatter],
                    decoration: InputDecoration(
                      labelText: draft.creditMarkupKind == 'PERCENT'
                          ? 'Percent'
                          : 'Peso amount',
                      hintText: '0.00',
                      suffixText: draft.creditMarkupKind == 'PERCENT'
                          ? '%'
                          : null,
                      prefixText: draft.creditMarkupKind == 'AMOUNT'
                          ? '₱ '
                          : null,
                    ),
                    validator: (raw) {
                      final text = (raw ?? '').trim();
                      if (text.isEmpty) return 'Enter the utang markup.';
                      final value = double.tryParse(text);
                      if (value == null || !value.isFinite || value < 0) {
                        return 'Enter 0 or more.';
                      }
                      if (draft.creditMarkupKind == 'PERCENT' && value > 1000) {
                        return 'At most 1000%.';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: ValueKey('$keyPrefix-code-$index'),
            controller: draft.code,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            decoration: const InputDecoration(
              labelText: 'Factory barcode (leave blank to auto-generate)',
              hintText: 'Scan or type the barcode for this selling unit',
              prefixIcon: Icon(Icons.barcode_reader),
              helperText: 'Each selling unit gets its own scannable barcode.',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SellingUnitHelper(
            draft: draft,
            baseCode: baseCode,
            units: units,
            basePrice: widget.basePrice,
          ),
        ],
      ),
    );
  }
}

/// Live preview of what the new selling unit equals in base units and price:
/// "1 BAG = 40 KG · ₱6.75 per KG" or "1 PC = 0.05 BOX · ₱600.00 per BOX" plus
/// the inverse count ("20 PC = 1 BOX") whenever the new unit is smaller than 1
/// base unit.
class SellingUnitHelper extends StatelessWidget {
  const SellingUnitHelper({
    super.key,
    required this.draft,
    required this.baseCode,
    required this.units,
    this.basePrice,
  });

  final SellingUnitDraft draft;
  final String baseCode;
  final List<UnitOfMeasure> units;
  final double? basePrice;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        draft.factor,
        draft.price,
        draft.creditMarkupValue,
      ]),
      builder: (context, _) {
        final factor = double.tryParse(draft.factor.text.trim());
        final price = double.tryParse(draft.price.text.trim());
        if (factor == null || factor <= 0 || price == null || price < 0) {
          return const SizedBox.shrink();
        }
        final unitCode = _codeFor(draft.uomId);
        final creditVal = draft.resolvedCreditValue;
        final double? creditPrice = switch (draft.creditMarkupKind) {
          'AMOUNT' when creditVal > 0 => price + creditVal,
          'PERCENT' when creditVal > 0 => price * (1 + creditVal / 100),
          _ => null,
        };
        return Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.small),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '1 $unitCode = ${formatQuantity(factor)} $baseCode · '
                'per-$baseCode equivalent ${formatPeso(price / factor)}'
                '${basePrice != null ? ' vs your $baseCode price ${formatPeso(basePrice!)}' : ''}',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (factor < 1)
                Text(
                  '${formatQuantity(1 / factor)} $unitCode = 1 $baseCode',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              if (creditPrice != null)
                Text(
                  'Utang price: ${formatPeso(creditPrice)} per $unitCode',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        );
      },
    );
  }

  String _codeFor(int? uomId) {
    for (final unit in units) {
      if (unit.id == uomId) return unit.code;
    }
    return 'unit';
  }
}

/// Adds one selling unit to an existing variant, with the same pricing, utang
/// markup, barcode, and validation rules as the Add/Edit Product form.
///
/// Shared by [ProductsDetailsDialog] and [ProductsFormDialog] (Edit mode) so
/// adding a selling unit is identical from either screen.
class AddSellingUnitDialog extends StatefulWidget {
  const AddSellingUnitDialog({
    super.key,
    required this.productName,
    required this.variant,
    required this.units,
    required this.onSubmit,
    this.onCreateUnit,
  });

  final String productName;
  final ProductVariant variant;
  final List<UnitOfMeasure> units;
  final Future<String?> Function(NewSellingUnit unit) onSubmit;
  final InlineUnitCreator? onCreateUnit;

  @override
  State<AddSellingUnitDialog> createState() => _AddSellingUnitDialogState();
}

class _AddSellingUnitDialogState extends State<AddSellingUnitDialog> {
  final _formKey = GlobalKey<FormState>();
  final _draft = SellingUnitDraft();
  late final List<UnitOfMeasure> _units = List<UnitOfMeasure>.of(widget.units);
  String? _error;
  bool _saving = false;

  Future<({UnitOfMeasure? unit, String? error})> _handleCreateUnit({
    required String code,
    required String name,
  }) async {
    final creator = widget.onCreateUnit;
    if (creator == null) return (unit: null, error: 'Cannot create unit.');
    final res = await creator(code: code, name: name);
    if (mounted && res.unit != null && !_units.any((u) => u.id == res.unit!.id)) {
      setState(() => _units.add(res.unit!));
    }
    return res;
  }

  double? get _basePrice {
    for (final unit in widget.variant.sellingUoms) {
      if (unit.uomId == widget.variant.baseUomId &&
          unit.conversionFactor == 1) {
        return unit.defaultSellingPrice;
      }
    }
    return null;
  }

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
      creditMarkupKind: _draft.creditMarkupKind,
      creditMarkupValue: _draft.resolvedCreditValue,
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
    Navigator.pop(context, unit);
  }

  String _codeFor(int? uomId) {
    for (final unit in _units) {
      if (unit.id == uomId) return unit.code;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return AppDialog(
      icon: Icons.add_box_outlined,
      title: 'Add pack / bulk unit',
      subtitle: '${widget.productName} · ${widget.variant.variantName}',
      width: 560,
      content: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
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
              basePrice: _basePrice,
              units: _units,
              onCreateUnit: widget.onCreateUnit == null
                  ? null
                  : _handleCreateUnit,
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
          child: Text(_saving ? 'Adding…' : 'Add pack unit'),
        ),
      ],
    );
  }
}

/// Directly adds a brand-new standalone variant to an existing product (e.g.
/// Nails → "Per Piece", "Per Kilo", "2 inch") with its own unit (including
/// inline custom unit creation), price, utang markup, barcode, initial stock,
/// and reorder level — zero conversion math or decimal limits.
class AddVariantDialog extends StatefulWidget {
  const AddVariantDialog({
    super.key,
    required this.productId,
    required this.productName,
    required this.units,
    required this.onSubmit,
    this.onCreateUnit,
  });

  final int productId;
  final String productName;
  final List<UnitOfMeasure> units;
  final Future<String?> Function(NewVariantDraft draft) onSubmit;
  final InlineUnitCreator? onCreateUnit;

  @override
  State<AddVariantDialog> createState() => _AddVariantDialogState();
}

class _AddVariantDialogState extends State<AddVariantDialog> {
  static final _decimalFormatter = FilteringTextInputFormatter.allow(
    RegExp(r'^-?\d*\.?\d{0,2}'),
  );

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _skuController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _costController = TextEditingController(text: '0');
  final _priceController = TextEditingController();
  final _creditValueController = TextEditingController();
  final _initialController = TextEditingController(text: '0');
  final _reorderController = TextEditingController(text: '10');
  late final List<UnitOfMeasure> _units = List<UnitOfMeasure>.of(widget.units);
  late int? _baseUomId = _units.firstOrNull?.id;
  String _creditKind = 'NONE';
  String? _error;
  bool _saving = false;

  UnitOfMeasure? get _selectedUnit {
    for (final u in _units) {
      if (u.id == _baseUomId) return u;
    }
    return null;
  }

  String get _unitCode => _selectedUnit?.code ?? 'unit';

  @override
  void dispose() {
    for (final c in [
      _nameController,
      _skuController,
      _barcodeController,
      _costController,
      _priceController,
      _creditValueController,
      _initialController,
      _reorderController,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _num(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '')) ?? 0;

  Future<void> _createCustomUnit() async {
    final creator = widget.onCreateUnit;
    if (creator == null) return;
    final created = await showCreateCustomUnitDialog(context, creator);
    if (!mounted || created == null) return;
    setState(() {
      if (!_units.any((u) => u.id == created.id)) {
        _units.add(created);
      }
      _baseUomId = created.id;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final unit = _selectedUnit;
    if (unit == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final draft = NewVariantDraft(
      productId: widget.productId,
      variantName: _nameController.text.trim(),
      sku: _skuController.text.trim(),
      baseUomId: unit.id,
      baseUomCode: unit.code,
      sellingPrice: _num(_priceController),
      minStockThreshold: _num(_reorderController),
      barcodeQr: _barcodeController.text.trim(),
      creditMarkupKind: _creditKind,
      creditMarkupValue: _creditKind == 'NONE'
          ? 0
          : _num(_creditValueController),
      openingQty: _num(_initialController),
      openingUnitCost: _num(_costController),
    );
    final message = await widget.onSubmit(draft);
    if (!mounted) return;
    if (message != null) {
      setState(() {
        _error = message;
        _saving = false;
      });
      return;
    }
    Navigator.pop(context, draft);
  }

  static String? _nonNegative(String? raw) {
    final value = double.tryParse((raw ?? '').trim().replaceAll(',', ''));
    if (value == null) return 'Enter a number.';
    if (value < 0) return 'Cannot be negative.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final unit = _selectedUnit;
    return AppDialog(
      icon: Icons.layers_outlined,
      title: 'Add variant',
      subtitle: widget.productName,
      width: 560,
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
              key: const ValueKey('new-variant-name'),
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Variant name',
                hintText: 'e.g. Per Piece, Per Box, 2 inch, 50kg',
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Enter a variant name.'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const ValueKey('new-variant-sku'),
              controller: _skuController,
              decoration: const InputDecoration(
                labelText: 'SKU (optional)',
                hintText: 'e.g. NAIL-PC-1IN',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: KeyedSubtree(
                    key: ValueKey('new-variant-uom-${_units.length}-$_baseUomId'),
                    child: DropdownButtonFormField<int>(
                      key: const ValueKey('new-variant-unit-picker'),
                      isExpanded: true,
                      initialValue: _baseUomId,
                      decoration: const InputDecoration(
                        labelText: 'Selling unit',
                        helperText: 'Standalone unit for this variant (no conversion needed).',
                      ),
                      items: [
                        for (final option in _units)
                          DropdownMenuItem(
                            value: option.id,
                            child: Text(
                              option.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      validator: (v) =>
                          v == null ? 'Choose or create a selling unit.' : null,
                      onChanged: (v) => setState(() => _baseUomId = v),
                    ),
                  ),
                ),
                if (widget.onCreateUnit != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: OutlinedButton.icon(
                      key: const ValueKey('new-variant-custom-unit'),
                      onPressed: _createCustomUnit,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('new-variant-cost'),
                    controller: _costController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_decimalFormatter],
                    decoration: InputDecoration(
                      labelText: 'Cost per $_unitCode',
                      hintText: '0.00',
                      prefixText: '₱ ',
                    ),
                    validator: _nonNegative,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('new-variant-price'),
                    controller: _priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_decimalFormatter],
                    decoration: InputDecoration(
                      labelText: 'Selling price per $_unitCode',
                      hintText: '0.00',
                      prefixText: '₱ ',
                    ),
                    validator: sellingUnitPriceError,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    key: const ValueKey('new-variant-credit-kind'),
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
                      DropdownMenuItem(value: 'PERCENT', child: Text('Percent')),
                    ],
                    onChanged: (v) =>
                        setState(() => _creditKind = v ?? 'NONE'),
                  ),
                ),
                if (_creditKind != 'NONE') ...[
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    flex: 2,
                    child: TextFormField(
                      key: const ValueKey('new-variant-credit-value'),
                      controller: _creditValueController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [_decimalFormatter],
                      decoration: InputDecoration(
                        labelText: _creditKind == 'PERCENT'
                            ? 'Percent'
                            : 'Peso amount',
                        hintText: '0.00',
                        suffixText: _creditKind == 'PERCENT' ? '%' : null,
                        prefixText: _creditKind == 'AMOUNT' ? '₱ ' : null,
                      ),
                      validator: (raw) {
                        final text = (raw ?? '').trim();
                        if (text.isEmpty) return 'Enter the utang markup.';
                        final value = double.tryParse(text);
                        if (value == null || !value.isFinite || value < 0) {
                          return 'Enter 0 or more.';
                        }
                        if (_creditKind == 'PERCENT' && value > 1000) {
                          return 'At most 1000%.';
                        }
                        return null;
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('new-variant-initial'),
                    controller: _initialController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_decimalFormatter],
                    decoration: InputDecoration(
                      labelText: 'Initial quantity',
                      hintText: '0',
                      suffixText: _unitCode,
                    ),
                    validator: (raw) {
                      final err = _nonNegative(raw);
                      if (err != null) return err;
                      final qty = _num(_initialController);
                      if (unit != null &&
                          unit.isWhole &&
                          qty != qty.roundToDouble()) {
                        return '${unit.code} is counted in whole numbers.';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('new-variant-reorder'),
                    controller: _reorderController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [_decimalFormatter],
                    decoration: InputDecoration(
                      labelText: 'Reorder level',
                      hintText: '10',
                      suffixText: _unitCode,
                    ),
                    validator: _nonNegative,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const ValueKey('new-variant-barcode'),
              controller: _barcodeController,
              inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
              decoration: const InputDecoration(
                labelText: 'Factory barcode (leave blank to auto-generate)',
                hintText: 'Scan or type the barcode for this variant',
                prefixIcon: Icon(Icons.barcode_reader),
              ),
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
          key: const ValueKey('new-variant-submit'),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Adding…' : 'Add variant'),
        ),
      ],
    );
  }
}
