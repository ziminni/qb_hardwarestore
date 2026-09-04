import 'package:client/features/dashboard/viewmodels/dashboard_mock_data.dart';
import 'package:client/features/dashboard/widget/inventory_action_button.dart';
import 'package:client/features/dashboard/widget/inventory_data_table.dart';
import 'package:client/features/dashboard/widget/inventory_list_item.dart';
import 'package:client/features/dashboard/widget/inventory_metric_card.dart';
import 'package:client/features/dashboard/widget/inventory_section.dart';
import 'package:flutter/material.dart';

class InventoryDashboardContent extends StatelessWidget {
  const InventoryDashboardContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(
              child: Text(
                'Inventory overview',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            InventoryActionButton(label: 'Export', icon: Icons.download),
            SizedBox(width: 8),
            InventoryActionButton(label: 'Add product'),
          ],
        ),
        SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: DashboardMockData.inventoryMetrics
              .map(
                (metric) => SizedBox(
                  width: 190,
                  child: InventoryMetricCard(
                    label: metric.label,
                    value: metric.value,
                  ),
                ),
              )
              .toList(),
        ),
        SizedBox(height: 16),
        InventorySection(
          title: 'Inventory table',
          actionLabel: 'Search / Filter',
          child: InventoryDataTable(
            columns: DashboardMockData.inventoryTable.columns,
            rows: DashboardMockData.inventoryTable.rows,
          ),
        ),
        SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: InventorySection(
                title: 'Recent stock movements',
                child: Column(
                  children: DashboardMockData.stockMovements
                      .map(
                        (item) => InventoryListItem(
                          title: item.title,
                          subtitle: item.subtitle,
                          trailing: item.trailing,
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: InventorySection(
                title: 'Restock queue',
                child: Column(
                  children: DashboardMockData.restockQueue
                      .map(
                        (item) => InventoryListItem(
                          title: item.title,
                          subtitle: item.subtitle,
                          trailing: item.trailing,
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
