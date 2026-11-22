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
  String _category = ShiftCashMovement.otherCategory;
  final _amountController = TextEditingController();
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  double? get _amount {
    final parsed = double.tryParse(_amountController.text.trim());
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  String get _reason => _reasonController.text.trim();

  bool get _canSubmit => _amount != null && _reason.isNotEmpty;

  static IconData _categoryIcon(String key) => switch (key) {
    ShiftCashMovement.lunchCategory => Icons.restaurant_outlined,
    ShiftCashMovement.fuelCategory => Icons.local_gas_station_outlined,
    ShiftCashMovement.suppliesCategory => Icons.inventory_2_outlined,
    ShiftCashMovement.safeDropCategory => Icons.savings_outlined,
    _ => Icons.more_horiz_rounded,
  };

  String get _reasonHint {
    if (_kind != ShiftCashMovement.cashOutKind) {
      return 'e.g. Added change coins to drawer';
    }
    return switch (_category) {
      ShiftCashMovement.lunchCategory => 'e.g. Staff lunch allowance',
      ShiftCashMovement.fuelCategory => 'e.g. Delivery truck diesel',
      ShiftCashMovement.suppliesCategory => 'e.g. Receipt paper rolls, tape',
      ShiftCashMovement.safeDropCategory => 'e.g. Mid-day owner safe drop',
      _ => 'e.g. Petty cash expense',
    };
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record drawer cash in / out'),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Log cash taken out of the register or added to the drawer so '
                'your closing count matches expected cash.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.md),
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
              if (_kind == ShiftCashMovement.cashOutKind) ...[
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Category',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  key: const ValueKey('cash-movement-category'),
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry
                        in ShiftCashMovement.cashOutCategories.entries)
                      _CategoryTile(
                        key: ValueKey('cash-movement-cat-${entry.key}'),
                        icon: _categoryIcon(entry.key),
                        label: entry.value,
                        selected: _category == entry.key,
                        onTap: () => setState(() => _category = entry.key),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextField(
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
              const SizedBox(height: AppSpacing.md),
              TextField(
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
                    category: _kind == ShiftCashMovement.cashOutKind
                        ? _category
                        : ShiftCashMovement.changeFloatCategory,
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

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.brandBlack : AppColors.surfaceSunken,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        side: BorderSide(
          color: selected ? AppColors.brandGold : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: selected ? AppColors.brandGold : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? AppColors.brandWhite
                      : AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
