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
  _ConversionMode _mode = _ConversionMode.direct;
  String? _subUnitHintError;

  SellingUnitDraft get draft => widget.draft;
  int get index => widget.index;
  String get keyPrefix => widget.keyPrefix;
  String get baseCode => widget.baseCode;
  List<UnitOfMeasure> get units => widget.units;

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
    final hasPickedUnit = draft.uomId != null;
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
                child: DropdownButtonFormField<int>(
                  key: ValueKey('$keyPrefix-unit-$index'),
                  isExpanded: true,
                  initialValue: draft.uomId,
                  decoration: const InputDecoration(
                    labelText: 'Selling unit',
                    helperText: 'e.g. PC, BOX, BAG, PACK, KG',
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
                    labelText: hasPickedUnit
                        ? 'How many $baseCode per $selectedCode'
                        : 'How many $baseCode',
                    hintText: _mode == _ConversionMode.subUnit ? '0.05' : '40',
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
                  decoration: InputDecoration(
                    labelText: hasPickedUnit
                        ? 'Selling price per $selectedCode'
                        : 'Selling price per unit',
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
                '${formatPeso(price / factor)} per $baseCode',
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
  });

  final String productName;
  final ProductVariant variant;
  final List<UnitOfMeasure> units;
  final Future<String?> Function(NewSellingUnit unit) onSubmit;

  @override
  State<AddSellingUnitDialog> createState() => _AddSellingUnitDialogState();
}

class _AddSellingUnitDialogState extends State<AddSellingUnitDialog> {
  final _formKey = GlobalKey<FormState>();
  final _draft = SellingUnitDraft();
  String? _error;
  bool _saving = false;

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
          child: Text(_saving ? 'Adding…' : 'Add unit'),
        ),
      ],
    );
  }
}
