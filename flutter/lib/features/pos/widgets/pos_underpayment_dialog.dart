import 'package:client/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

/// What the cashier chose when a sale came up short.
///
/// Three outcomes, not two, because decision 14 made anonymity a third case: an anonymous
/// sale cannot go into utang (the server answers `400 WALK_IN_CANNOT_OWE`), so "record the
/// utang" is not always available and the cashier needs a route out that is not simply
/// giving up.
enum PosUnderpaymentChoice {
  /// Take the full amount instead. Submits **nothing**, leaves the cart intact.
  collectFull,

  /// A **named** account: charge the shortfall to it. This is Phase 3's behaviour.
  recordUtang,

  /// An **anonymous** sale: record a customer first, so the debt belongs to somebody.
  nameCustomer,
}

/// Asks the cashier what to do about an underpaid sale BEFORE it is submitted.
///
/// Decision 06 section 4, extended by decision 14. The server posts a `CollectibleLedger` for
/// any shortfall, so submitting an accidental underpayment creates a real, recorded debt - and
/// the receipt prints afterwards, so without this step a mistyped amount would become an
/// obligation nobody noticed.
///
/// Returns a [PosUnderpaymentChoice], or null when dismissed. Null and [collectFull] both
/// submit nothing; this returns a value rather than acting, which is what keeps "nothing has
/// been submitted yet" true.
class PosUnderpaymentDialog extends StatelessWidget {
  const PosUnderpaymentDialog({
    super.key,
    required this.total,
    required this.amountPaid,
    required this.customerName,
    required this.isAnonymous,
  });

  final double total;
  final double amountPaid;
  final String customerName;

  /// True when no account is selected, in which case the shortfall cannot be booked.
  final bool isAnonymous;

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
            _row(
              context,
              isAnonymous ? 'Short' : 'To utang',
              shortfall,
              emphasise: true,
            ),
            const SizedBox(height: AppSpacing.md),
            ...isAnonymous ? _anonymousBody(theme) : _namedBody(theme),
          ],
        ),
      ),
      actions: isAnonymous
          ? [
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, PosUnderpaymentChoice.collectFull),
                child: const Text('Collect the full amount'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, PosUnderpaymentChoice.nameCustomer),
                child: const Text('Record a customer for this utang'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go back'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.pop(context, PosUnderpaymentChoice.recordUtang),
                child: const Text('Record the utang'),
              ),
            ],
    );
  }

  List<Widget> _namedBody(ThemeData theme) => [
    Text('Charge to:  $customerName'),
    const SizedBox(height: AppSpacing.xs),
    Text('Due in:  30 days', style: theme.textTheme.bodySmall),
    const SizedBox(height: AppSpacing.sm),
    Text(
      'This records a receivable against the customer. Nothing has been '
      'submitted yet.',
      style: theme.textTheme.bodySmall,
    ),
  ];

  /// Deliberately does NOT promise a receivable: booking this shortfall against the shared
  /// Walk-in placeholder is exactly what the server now refuses, and copy that promised one
  /// would be a lie the cashier only discovers at the receipt.
  List<Widget> _anonymousBody(ThemeData theme) => [
    Text('This sale is for:  $customerName'),
    const SizedBox(height: AppSpacing.xs),
    Text(
      'An anonymous sale cannot go into utang - there is nobody to collect it '
      'from. Collect the full amount, or record a customer to owe it.',
      style: theme.textTheme.bodySmall,
    ),
    const SizedBox(height: AppSpacing.sm),
    Text('Nothing has been submitted yet.', style: theme.textTheme.bodySmall),
  ];

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
