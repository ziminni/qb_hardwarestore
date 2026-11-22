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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record drawer cash in / out'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Log cash taken out of the register (owner drop, petty cash) or '
              'added to the drawer so your closing count matches expected cash.',
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
              DropdownButtonFormField<String>(
                key: const ValueKey('cash-movement-category'),
                initialValue: _category,
                decoration: const InputDecoration(
                  labelText: 'Category',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final entry
                      in ShiftCashMovement.cashOutCategories.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _category = value);
                },
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
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _reasonController,
              decoration: InputDecoration(
                labelText: 'Reason (required)',
                hintText: _kind == ShiftCashMovement.cashOutKind
                    ? 'e.g. Owner safe drop, delivery fuel allowance'
                    : 'e.g. Added change coins to drawer',
              ),
              maxLength: 255,
              onChanged: (_) => setState(() {}),
            ),
          ],
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
