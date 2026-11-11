import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/catalogue_option.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One extra selling unit being typed: "1 Bag = 40 kg at ₱270".
///
/// A row owns its controllers and its picked unit id, so removing the row in the
/// middle of a list cannot shuffle another row's typed text. Shared by the Add
/// product form and the details dialog's "Add selling unit" (Phase 1d Task 9).
class SellingUnitDraft {
  final factor = TextEditingController();
  final price = TextEditingController();
  final code = TextEditingController();
  int? uomId;

  void dispose() {
    factor.dispose();
    price.dispose();
    code.dispose();
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

/// The fields of ONE extra selling unit: unit, factor, price, optional code and
/// the live per-base-unit helper.
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
  final String? Function(int?)? validateUnit;
  final String? Function(String?)? validateFactor;
  final String? Function(String?)? validatePrice;
  final VoidCallback? onRemove;
  final bool autofocus;

  @override
  State<SellingUnitFields> createState() => _SellingUnitFieldsState();
}

class _SellingUnitFieldsState extends State<SellingUnitFields> {
  SellingUnitDraft get draft => widget.draft;
  int get index => widget.index;
  String get keyPrefix => widget.keyPrefix;
  String get baseCode => widget.baseCode;
  List<UnitOfMeasure> get units => widget.units;

  @override
  Widget build(BuildContext context) {
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  key: ValueKey('$keyPrefix-unit-$index'),
                  isExpanded: true,
                  initialValue: draft.uomId,
                  decoration: const InputDecoration(labelText: 'Selling unit'),
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
                  decoration: InputDecoration(
                    labelText: 'How many $baseCode',
                    hintText: '40',
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
                  decoration: const InputDecoration(
                    labelText: 'Price per unit',
                    prefixText: '₱ ',
                  ),
                  validator: widget.validatePrice,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          TextFormField(
            key: ValueKey('$keyPrefix-code-$index'),
            controller: draft.code,
            inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
            decoration: const InputDecoration(
              labelText: 'Unit code (optional)',
              hintText: 'Leave blank for an automatic QB code',
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SellingUnitHelper(draft: draft, baseCode: baseCode, units: units),
        ],
      ),
    );
  }
}

/// "1 Bag = 40 kg · ₱6.75 per kg", recomputed as the clerk types.
///
/// It answers the question the two number fields raise together: what does this
/// package work out to per base unit?
class SellingUnitHelper extends StatelessWidget {
  const SellingUnitHelper({
    super.key,
    required this.draft,
    required this.baseCode,
    required this.units,
  });

  final SellingUnitDraft draft;
  final String baseCode;
  final List<UnitOfMeasure> units;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([draft.factor, draft.price]),
      builder: (context, _) {
        final factor = double.tryParse(draft.factor.text.trim());
        final price = double.tryParse(draft.price.text.trim());
        if (factor == null || factor <= 0 || price == null || price < 0) {
          return const SizedBox.shrink();
        }
        final unitCode = _codeFor(draft.uomId);
        return Text(
          '1 $unitCode = ${formatQuantity(factor)} $baseCode · '
          '${formatPeso(price / factor)} per $baseCode',
          style: Theme.of(context).textTheme.bodySmall,
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
