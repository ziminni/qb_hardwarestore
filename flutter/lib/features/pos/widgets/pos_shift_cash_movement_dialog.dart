import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:flutter/material.dart';

class _CashMovementInput {
  const _CashMovementInput({
    required this.kind,
    required this.category,
    required this.amount,
    required this.reason,
  });

  final String kind;
  final String category;
  final double amount;
  final String reason;
}

/// Opens a dialog for a cashier to record a mid-shift cash withdrawal
/// (`CASH_OUT`, e.g. owner drop / petty cash) or addition (`CASH_IN`, e.g.
/// extra change coins) on their open shift.
Future<Shift?> showShiftCashMovementDialog(
  BuildContext context,
  ShiftViewmodel viewmodel,
) async {
  final shift = viewmodel.currentShift;
  if (shift == null) return null;

  final input = await showDialog<_CashMovementInput>(
    context: context,
    builder: (dialogContext) => const _ShiftCashMovementDialog(),
  );
  if (input == null) return null;

  final updated = await viewmodel.recordCashMovement(
    kind: input.kind,
    category: input.category,
    amount: input.amount,
    reason: input.reason,
  );
  if (!context.mounted) return updated;
  if (updated == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          viewmodel.actionError ?? 'The cash movement could not be recorded.',
        ),
      ),
    );
    return null;
  }
  return updated;
}

class _ShiftCashMovementDialog extends StatefulWidget {
  const _ShiftCashMovementDialog();

  @override
  State<_ShiftCashMovementDialog> createState() =>
      _ShiftCashMovementDialogState();
}

class _ShiftCashMovementDialogState extends State<_ShiftCashMovementDialog> {
  String _kind = ShiftCashMovement.cashOutKind;
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  final _reasonController = TextEditingController();

  static const List<({String key, String label})> _categorySuggestions = [
    (key: ShiftCashMovement.lunchCategory, label: 'Lunch'),
    (key: ShiftCashMovement.fuelCategory, label: 'Fuel'),
    (key: ShiftCashMovement.suppliesCategory, label: 'Supplies'),
    (key: ShiftCashMovement.safeDropCategory, label: 'Safe drop'),
    (key: 'UTILITIES', label: 'Utilities'),
    (key: 'DELIVERY', label: 'Delivery'),
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _categoryController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  double? get _amount {
    final parsed = double.tryParse(_amountController.text.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  String get _reason => _reasonController.text.trim();

  String get _resolvedCategory {
    if (_kind != ShiftCashMovement.cashOutKind) {
      return ShiftCashMovement.changeFloatCategory;
    }
    final raw = _categoryController.text.trim();
    if (raw.isEmpty) return ShiftCashMovement.otherCategory;
    final normalized = raw.toUpperCase().replaceAll(' ', '_');
    if (ShiftCashMovement.cashOutCategories.containsKey(normalized)) {
      return normalized;
    }
    return raw;
  }

  bool get _canSubmit => _amount != null && _reason.isNotEmpty;

  String get _reasonHint {
    if (_kind != ShiftCashMovement.cashOutKind) {
      return 'e.g. Added change coins to drawer';
    }
    return switch (_resolvedCategory) {
      ShiftCashMovement.lunchCategory => 'e.g. Staff lunch allowance',
      ShiftCashMovement.fuelCategory => 'e.g. Delivery truck diesel',
      ShiftCashMovement.suppliesCategory => 'e.g. Receipt paper rolls, tape',
      ShiftCashMovement.safeDropCategory => 'e.g. Mid-day owner safe drop',
      _ => 'e.g. Petty cash expense or receipt note',
    };
  }

  @override
  Widget build(BuildContext context) {
    final currentCategoryText = _categoryController.text.trim().toLowerCase();
    final isCashOut = _kind == ShiftCashMovement.cashOutKind;
    return AlertDialog(
      title: const Text('Record drawer cash in / out'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment<String>(
                    value: ShiftCashMovement.cashOutKind,
                    label: Text('Cash taken out'),
                    icon: Icon(Icons.call_made, size: 18),
                  ),
                  ButtonSegment<String>(
                    value: ShiftCashMovement.cashInKind,
                    label: Text('Cash added'),
                    icon: Icon(Icons.call_received, size: 18),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (selection) {
                  setState(() => _kind = selection.first);
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: isCashOut
                      ? AppColors.errorTint
                      : AppColors.successTint,
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                ),
                child: Row(
                  children: [
                    Icon(
                      isCashOut
                          ? Icons.remove_circle_outline
                          : Icons.add_circle_outline,
                      size: 16,
                      color: isCashOut
                          ? AppColors.errorText
                          : AppColors.successText,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isCashOut
                            ? 'Cash Out (Expense / Drop): subtracts from expected drawer cash.'
                            : 'Cash In (Change / Top-up): adds to expected drawer cash.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isCashOut
                              ? AppColors.errorText
                              : AppColors.successText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const ValueKey('cash-movement-amount'),
                controller: _amountController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  prefixText: '₱ ',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),
              if (_kind == ShiftCashMovement.cashOutKind) ...[
                const SizedBox(height: AppSpacing.md),
                TextField(
                  key: const ValueKey('cash-movement-category-input'),
                  controller: _categoryController,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: 'Category (optional)',
                    hintText: 'Type any label or tap a suggestion below',
                    border: OutlineInputBorder(),
                    counterText: '',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                Wrap(
                  key: const ValueKey('cash-movement-category'),
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final item in _categorySuggestions)
                      _CategorySuggestionChip(
                        key: ValueKey('cash-movement-cat-${item.key}'),
                        label: item.label,
                        selected:
                            currentCategoryText == item.label.toLowerCase() ||
                            currentCategoryText == item.key.toLowerCase(),
                        onTap: () {
                          setState(() {
                            _categoryController.text = item.label;
                            _categoryController.selection =
                                TextSelection.collapsed(
                                  offset: item.label.length,
                                );
                          });
                        },
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextField(
                key: const ValueKey('cash-movement-reason'),
                controller: _reasonController,
                decoration: InputDecoration(
                  labelText: 'Reason (required)',
                  hintText: _reasonHint,
                  border: const OutlineInputBorder(),
                ),
                maxLength: 255,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: !_canSubmit
              ? null
              : () => Navigator.of(context).pop(
                  _CashMovementInput(
                    kind: _kind,
                    category: _resolvedCategory,
                    amount: _amount!,
                    reason: _reason,
                  ),
                ),
          child: const Text('Save movement'),
        ),
      ],
    );
  }
}

class _CategorySuggestionChip extends StatelessWidget {
  const _CategorySuggestionChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brandBlack : AppColors.surfaceSunken,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.small),
        side: BorderSide(
          color: selected ? AppColors.brandGold : AppColors.border,
          width: selected ? 1.25 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: selected ? AppColors.brandWhite : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
