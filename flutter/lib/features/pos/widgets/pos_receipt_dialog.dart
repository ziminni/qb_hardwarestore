import 'package:client/data/models/pos_transaction.dart';
import 'package:flutter/material.dart';

class PosReceiptDialog extends StatelessWidget {
  const PosReceiptDialog({super.key, required this.receipt});
  final PosReceipt receipt;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.check_circle_outline),
          SizedBox(width: 10),
          Text('Transaction complete'),
        ],
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Reference: ${receipt.reference}'),
              Text('Payment: ${receipt.paymentMethod}'),
              const Divider(height: 28),
              ...receipt.lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${line.productName}\n${line.quantity.toStringAsFixed(2)} ${line.unit}',
                        ),
                      ),
                      Text('₱${line.total.toStringAsFixed(2)}'),
                    ],
                  ),
                ),
              ),
              const Divider(),
              _amountRow('Total', receipt.total),
              _amountRow('Paid', receipt.amountPaid),
              _amountRow('Change', receipt.change),
              const SizedBox(height: 12),
              const Text(
                'Inventory quantities were updated in the current app session.',
              ),
            ],
          ),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('New transaction'),
        ),
      ],
    );
  }

  Widget _amountRow(String label, double value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(label)),
        Text('₱${value.toStringAsFixed(2)}'),
      ],
    ),
  );
}
