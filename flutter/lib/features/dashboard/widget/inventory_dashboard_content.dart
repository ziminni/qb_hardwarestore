import 'package:client/features/dashboard/viewmodels/dashboard_mock_data.dart';
import 'package:client/features/dashboard/widget/inventory_action_button.dart';
import 'package:client/features/dashboard/widget/inventory_data_table.dart';
import 'package:client/features/dashboard/widget/inventory_list_item.dart';
import 'package:client/features/dashboard/widget/inventory_metric_card.dart';
import 'package:client/features/dashboard/widget/inventory_section.dart';
import 'package:client/shared/widgets/section_heading.dart';
import 'package:flutter/material.dart';

class InventoryDashboardContent extends StatelessWidget {
  const InventoryDashboardContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading(
          title: 'Inventory overview',
          subtitle: 'Today’s stock position at a glance',
          trailing: [
            InventoryActionButton(label: 'Export', icon: Icons.download),
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
