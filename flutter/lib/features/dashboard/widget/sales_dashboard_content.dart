import 'package:client/features/dashboard/widget/mock_action.dart';
import 'package:client/features/dashboard/widget/mock_metric.dart';
import 'package:client/features/dashboard/widget/mock_section.dart';
import 'package:client/features/dashboard/widget/mock_table.dart';
import 'package:flutter/material.dart';

class SalesDashboardContent extends StatelessWidget {
  const SalesDashboardContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Sales overview',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            MockAction(label: 'Select date range', icon: Icons.calendar_today),
            SizedBox(width: 8),
            MockAction(label: 'Export report', icon: Icons.download),
          ],
        ),
        SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 190,
              child: MockMetric(label: 'Gross sales', value: '₱ 0.00'),
            ),
            SizedBox(
              width: 190,
              child: MockMetric(label: 'Transactions', value: '0'),
            ),
            SizedBox(
              width: 190,
              child: MockMetric(label: 'Average sale', value: '₱ 0.00'),
            ),
            SizedBox(
              width: 190,
              child: MockMetric(label: 'Items sold', value: '0'),
            ),
          ],
        ),
        SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: MockSection(
                title: 'Sales trend / chart placeholder',
                child: SizedBox(
                  height: 220,
                  child: Center(child: Text('[ SALES CHART ]')),
                ),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: MockSection(
                title: 'Sales by category',
                child: SizedBox(
                  height: 220,
                  child: Center(child: Text('[ CATEGORY CHART ]')),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        MockSection(
          title: 'Recent transactions',
          actionLabel: 'View all',
          child: MockTable(
            columns: [
              'Receipt',
              'Date / Time',
              'Cashier',
              'Items',
              'Payment',
              'Total',
            ],
            rows: [
              ['[ # ]', '[ Date ]', '[ Cashier ]', '0', '[ Method ]', '₱ 0.00'],
              ['[ # ]', '[ Date ]', '[ Cashier ]', '0', '[ Method ]', '₱ 0.00'],
              ['[ # ]', '[ Date ]', '[ Cashier ]', '0', '[ Method ]', '₱ 0.00'],
            ],
          ),
        ),
      ],
    );
  }
}
