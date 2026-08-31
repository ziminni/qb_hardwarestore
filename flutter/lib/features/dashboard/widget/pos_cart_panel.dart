import 'package:client/features/dashboard/widget/mock_section.dart';
import 'package:client/features/dashboard/widget/pos_total_row.dart';
import 'package:flutter/material.dart';

class PosCartPanel extends StatelessWidget {
  const PosCartPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return MockSection(
      title: 'Current transaction',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TextField(
            decoration: InputDecoration(
              labelText: 'Customer (optional)',
              hintText: '[ Select customer ]',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          const SizedBox(
            height: 220,
            child: Center(child: Text('[ CART ITEMS ]')),
          ),
          const Divider(),
          const PosTotalRow(label: 'Subtotal', value: '₱ 0.00'),
          const PosTotalRow(label: 'Discount', value: '₱ 0.00'),
          const PosTotalRow(label: 'Tax', value: '₱ 0.00'),
          const Divider(),
          const PosTotalRow(label: 'TOTAL', value: '₱ 0.00', emphasized: true),
          const SizedBox(height: 14),
          const ElevatedButton(
            onPressed: null,
            child: Text('Proceed to payment'),
          ),
          const SizedBox(height: 8),
          const OutlinedButton(
            onPressed: null,
            child: Text('Clear transaction'),
          ),
        ],
      ),
    );
  }
}
