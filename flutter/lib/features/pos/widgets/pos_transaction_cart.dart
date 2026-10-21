import 'package:client/core/constants/app_colors.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/widgets/pos_utang_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PosTransactionCart extends StatelessWidget {
  const PosTransactionCart({
    super.key,
    required this.onPayment,
    required this.onClear,
    required this.onChangeCustomer,
    this.onHold,
  });

  final VoidCallback onPayment;
  final VoidCallback onClear;

  /// Parks the basket without taking money (Phase 3 held sale).
  ///
  /// Optional because the cart is built by tests and screens with no held-cart
  /// queue behind them; when null the action is absent rather than shown dead.
  final VoidCallback? onHold;

  /// Opens the customer picker. The sale's account is [PosTransactionViewmodel]
  /// state, so this row only reports the selection and asks to change it.
  final VoidCallback onChangeCustomer;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PosTransactionViewmodel>();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Current sale',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Spacer(),
                Text('${state.itemCount} line item(s)'),
              ],
            ),
            // Decision 14: who is paying sits above what they are paying for, so the cashier
            // sees the account before assembling the basket. An anonymous sale is marked as
            // such, because that is the difference between "paid in full" and "becomes a
            // debt" - and a walk-in CANNOT owe.
            InkWell(
              onTap: onChangeCustomer,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    const Icon(Icons.person_outline, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        state.customerLabel,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: state.selectedCustomer == null
                              ? AppColors.textSecondary
                              : null,
                        ),
                      ),
                    ),
                    const Text('Change', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
            // Decision 14: the balance sits with the account, at the till, because a credit
            // limit is only weighable where the sale is being decided.
            PosUtangPanel(
              customer: state.selectedCustomer,
              summary: state.ledgerSummary,
              error: state.ledgerError,
              isLoading: state.isLoadingLedger,
              thisSaleTotal: state.total,
            ),
            const Divider(height: 28),
            Expanded(
              child: state.lines.isEmpty
                  ? const Center(
                      child: Text(
                        'Select a product to begin.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      itemCount: state.lines.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final line = state.lines[index];
                        // Decision 06 section 3: a short-stock rejection is recoverable
                        // in place, so the cart names the row the cashier must fix.
                        // Without this the viewmodel's marker would be a fact nothing
                        // shows - the same defect the final review found, one layer up.
                        final isShort =
                            line.variantUomId == state.insufficientStockLineId;
                        final breakdown =
                            '${line.variantName}\n'
                            '${line.quantity.toStringAsFixed(2)} ${line.unit} × '
                            '₱${line.unitPrice.toStringAsFixed(2)}';
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          tileColor: isShort
                              ? Theme.of(context).colorScheme.errorContainer
                              : null,
                          shape: isShort
                              ? RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                )
                              : null,
                          title: Text(line.productName),
                          subtitle: Text(
                            isShort
                                ? '$breakdown\nNot enough stock — reduce this line.'
                                : breakdown,
                            style: isShort
                                ? TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer,
                                  )
                                : null,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '₱${line.total.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove',
                                onPressed: () => state.removeLine(index),
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const Divider(),
            Row(
              children: [
                Text('TOTAL', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                Text(
                  '₱${state.total.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: state.lines.isEmpty ? null : onPayment,
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Proceed to payment'),
            ),
            const SizedBox(height: 8),
            // Decision 03: a cashier must be able to park a half-rung basket when
            // the customer walks away. Disabled on an empty cart for the same
            // reason Pay is: a hold with no lines leaves a row that resumes to
            // nothing.
            if (onHold != null) ...[
              OutlinedButton(
                onPressed: state.lines.isEmpty ? null : onHold,
                child: const Text('Hold transaction'),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton(
              onPressed: state.lines.isEmpty ? null : onClear,
              child: const Text('Clear transaction'),
            ),
          ],
        ),
      ),
    );
  }
}
