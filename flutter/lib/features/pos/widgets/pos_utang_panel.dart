import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/customer.dart';
import 'package:flutter/material.dart';

/// The utang panel shown at the till for the customer a sale is addressed to.
///
/// Decision 14 put this here rather than on a separate screen because "charge it to my
/// account" is only meaningful if the balance is visible **where the decision is made** - a
/// cashier cannot weigh a credit limit on another page.
///
/// Stateless and driven by explicit values, including [thisSaleTotal], so the credit-limit
/// warning can be reasoned about without a running server.
class PosUtangPanel extends StatelessWidget {
  const PosUtangPanel({
    super.key,
    required this.customer,
    required this.summary,
    required this.error,
    required this.isLoading,
    required this.thisSaleTotal,
  });

  /// Null for an anonymous sale, in which case there is nothing to show.
  final Customer? customer;
  final CustomerLedgerSummary? summary;
  final String? error;
  final bool isLoading;

  /// What this sale would add to the account, for the limit warning.
  final double thisSaleTotal;

  @override
  Widget build(BuildContext context) {
    final selected = customer;

    // An anonymous sale cannot owe (decision 14), so there is no balance to show - and saying
    // so is better than an empty box, because it tells the cashier WHY there is nothing.
    if (selected == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text(
          'Anonymous sale — no account to charge.',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      );
    }

    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    // A failed load says so rather than showing 0.00, because a zero balance is a claim that
    // the customer owes nothing.
    final loadError = error;
    if (loadError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          loadError,
          style: const TextStyle(fontSize: 12, color: AppColors.error),
        ),
      );
    }

    final owed = summary;
    final balance = owed?.totalBalance ?? 0;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${selected.type.label} · ',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                balance > 0 ? '${formatPeso(balance)} outstanding' : 'No utang',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: balance > 0
                      ? AppColors.error
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (owed != null && owed.hasDebt)
            Text(
              '${owed.openCount} open · ${owed.overdueCount} overdue',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          _buildLimitLine(context, selected, balance),
        ],
      ),
    );
  }

  Widget _buildLimitLine(
    BuildContext context,
    Customer selected,
    double balance,
  ) {
    // "0" means NOT SET, so a customer without a configured limit gets a neutral note rather
    // than a warning. Warning on 0 would fire for every customer on every utang sale.
    if (!selected.hasCreditLimit) {
      return const Text(
        'No credit limit set',
        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
      );
    }

    final projected = balance + thisSaleTotal;
    final over = projected - selected.totalCreditLimit;
    if (over <= 0) {
      return Text(
        'Limit ${formatPeso(selected.totalCreditLimit)} · '
        '${formatPeso((selected.totalCreditLimit - projected))} headroom',
        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
      );
    }

    // ADVISORY, never a block: the limit defaults to 0 and a hard block would refuse a sale a
    // manager might well approve.
    return Text(
      '⚠ This sale would take them ${formatPeso(over)} over the '
      '${formatPeso(selected.totalCreditLimit)} limit.',
      style: const TextStyle(fontSize: 11, color: AppColors.error),
    );
  }
}
