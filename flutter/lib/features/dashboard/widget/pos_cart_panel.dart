import 'package:client/features/dashboard/viewmodels/dashboard_mock_data.dart';
import 'package:client/features/dashboard/widget/pos_total_row.dart';
import 'package:client/features/dashboard/widget/pos_section.dart';
import 'package:flutter/material.dart';

class PosCartPanel extends StatelessWidget {
  const PosCartPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const PosSection(
      title: 'Current transaction',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            decoration: InputDecoration(
              labelText: 'Customer (optional)',
              hintText: 'Select customer',
              border: OutlineInputBorder(),
            ),
          ),
          SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: Center(child: Text(DashboardMockData.posCartSummary)),
          ),
          Divider(),
          PosTotalRow(label: 'Subtotal', value: DashboardMockData.posSubtotal),
          PosTotalRow(label: 'Discount', value: DashboardMockData.posDiscount),
          PosTotalRow(label: 'Tax', value: DashboardMockData.posTax),
          Divider(),
          PosTotalRow(
            label: 'TOTAL',
            value: DashboardMockData.posTotal,
            emphasized: true,
          ),
          SizedBox(height: 14),
          ElevatedButton(onPressed: null, child: Text('Proceed to payment')),
          SizedBox(height: 8),
          OutlinedButton(onPressed: null, child: Text('Clear transaction')),
        ],
      ),
    );
  }
}
