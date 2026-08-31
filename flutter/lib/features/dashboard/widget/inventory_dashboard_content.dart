import 'package:client/features/dashboard/widget/mock_action.dart';
import 'package:client/features/dashboard/widget/mock_list_row.dart';
import 'package:client/features/dashboard/widget/mock_metric.dart';
import 'package:client/features/dashboard/widget/mock_section.dart';
import 'package:client/features/dashboard/widget/mock_table.dart';
import 'package:flutter/material.dart';

class InventoryDashboardContent extends StatelessWidget {
  const InventoryDashboardContent({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Inventory overview',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            MockAction(label: 'Export', icon: Icons.download),
            SizedBox(width: 8),
            MockAction(label: 'Add product'),
          ],
        ),
        SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 190,
              child: MockMetric(label: 'Total products', value: '0'),
            ),
            SizedBox(
              width: 190,
              child: MockMetric(label: 'Inventory value', value: '₱ 0.00'),
            ),
            SizedBox(
              width: 190,
              child: MockMetric(label: 'Low stock', value: '0'),
            ),
            SizedBox(
              width: 190,
              child: MockMetric(label: 'Out of stock', value: '0'),
            ),
          ],
        ),
        SizedBox(height: 16),
        MockSection(
          title: 'Inventory table',
          actionLabel: 'Search / Filter',
          child: MockTable(
            columns: [
              'Product',
              'Category',
              'On hand',
              'Reorder level',
              'Status',
            ],
            rows: [
              ['[ Product ]', '[ Category ]', '0', '0', '[ Status ]'],
              ['[ Product ]', '[ Category ]', '0', '0', '[ Status ]'],
              ['[ Product ]', '[ Category ]', '0', '0', '[ Status ]'],
            ],
          ),
        ),
        SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: MockSection(
                title: 'Recent stock movements',
                child: Column(
                  children: [
                    MockListRow(
                      title: '[ Product ]',
                      subtitle: '[ Reference ] · [ Time ]',
                      trailing: '+/- 0',
                    ),
                    Divider(),
                    MockListRow(
                      title: '[ Product ]',
                      subtitle: '[ Reference ] · [ Time ]',
                      trailing: '+/- 0',
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: MockSection(
                title: 'Restock queue',
                child: Column(
                  children: [
                    MockListRow(
                      title: '[ Product ]',
                      subtitle: '[ Suggested quantity ]',
                      trailing: '[ Priority ]',
                    ),
                    Divider(),
                    MockListRow(
                      title: '[ Product ]',
                      subtitle: '[ Suggested quantity ]',
                      trailing: '[ Priority ]',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
