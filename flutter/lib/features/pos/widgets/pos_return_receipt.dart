import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/returns.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:flutter/material.dart';

/// What the server posted, in the server's own numbers (C7 done state).
///
/// Debt reduced comes before cash refunded because that is the order the money
/// moved: the utang dropped first, and only the excess left the drawer. These
/// figures REPLACE the till's estimate; the estimate is never printed here.
class PosReturnReceipt extends StatelessWidget {
  const PosReturnReceipt({
    super.key,
    required this.result,
    required this.onStartAnother,
    this.transactionNo,
    this.lines = const [],
  });

  final ReturnResult result;
  final VoidCallback onStartAnother;

  /// The sale the goods came back from, so the slip can be filed against it.
  final String? transactionNo;

  /// What actually came back, named, so the cashier can check the counter
  /// against the slip in hand.
  final List<({String name, String uom, double qty})> lines;

  @override
  Widget build(BuildContext context) {
    final refund = result.refund;
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, color: AppColors.successText),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Return posted: ${result.returnNo}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          if (transactionNo case final number?) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Against $number',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
          if (lines.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  '${line.qty.toStringAsFixed(0)} ${line.uom} '
                  '${line.name}',
                ),
              ),
          ],
          const SizedBox(height: AppSpacing.md),
          Text('Return value ${formatPeso(refund.returnValue)}'),
          Text('Utang reduced ${formatPeso(refund.debtReduced)}'),
          Text(
            'Cash refunded ${formatPeso(refund.cashRefund)} '
            '(${refund.refundMethod})',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (refund.ledgerBalance case final balance?)
            Text('Ledger still owes ${formatPeso(balance)}')
          else
            const Text('This sale had nothing owing.'),
          const SizedBox(height: AppSpacing.md),
          const Text(
            'Hand the cash over and file the slip against the transaction. The '
            'figures above are the server\'s own.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: onStartAnother,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
              icon: const Icon(Icons.refresh),
              label: const Text('Start another return'),
            ),
          ),
        ],
      ),
    );
  }
}
