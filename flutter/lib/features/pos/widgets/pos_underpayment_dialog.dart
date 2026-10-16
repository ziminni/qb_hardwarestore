import 'package:client/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

/// Asks the cashier to confirm an underpaid sale BEFORE it is submitted.
///
/// Decision 06 section 4. The server posts a `CollectibleLedger` for any shortfall
/// (and a walk-in sale always has a customer, so this always applies), which means
/// submitting an accidental underpayment creates a real, recorded debt to somebody's
/// account. The receipt prints afterwards, so without this step a mistyped amount
/// would become an obligation nobody noticed.
///
/// Returns true to submit, null/false to go back - and going back submits NOTHING and
/// leaves the cart intact, which is why this returns a value rather than acting.
class PosUnderpaymentDialog extends StatelessWidget {
  const PosUnderpaymentDialog({
    super.key,
    required this.total,
    required this.amountPaid,
    required this.customerName,
  });

  final double total;
  final double amountPaid;
  final String customerName;

  double get shortfall => total - amountPaid;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Underpayment'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _row(context, 'Total', total),
            const SizedBox(height: AppSpacing.sm),
            _row(context, 'Paid', amountPaid),
            const Divider(height: AppSpacing.xl),
            _row(context, 'To utang', shortfall, emphasise: true),
            const SizedBox(height: AppSpacing.md),
            Text('Charge to:  $customerName'),
            const SizedBox(height: AppSpacing.xs),
            Text('Due in:  30 days', style: theme.textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'This records a receivable against the customer. Nothing has been '
              'submitted yet.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Go back'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Record the utang'),
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    double value, {
    bool emphasise = false,
  }) {
    final theme = Theme.of(context);
    final style = emphasise
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyMedium;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value.toStringAsFixed(2), style: style),
      ],
    );
  }
}
