import 'package:client/core/constants/app_colors.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class PosTransactionCart extends StatelessWidget {
  const PosTransactionCart({
    super.key,
    required this.onPayment,
    required this.onClear,
  });

  final VoidCallback onPayment;
  final VoidCallback onClear;

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
