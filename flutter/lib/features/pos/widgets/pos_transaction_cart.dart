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
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(line.productName),
                          subtitle: Text(
                            '${line.quantity.toStringAsFixed(2)} ${line.unit} × ₱${line.unitPrice.toStringAsFixed(2)}',
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
