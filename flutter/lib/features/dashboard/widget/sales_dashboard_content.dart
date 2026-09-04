import 'package:client/features/dashboard/viewmodels/dashboard_mock_data.dart';
import 'package:client/features/dashboard/widget/sales_action_button.dart';
import 'package:client/features/dashboard/widget/sales_data_table.dart';
import 'package:client/features/dashboard/widget/sales_metric_card.dart';
import 'package:client/features/dashboard/widget/sales_section.dart';
import 'package:flutter/material.dart';

class SalesDashboardContent extends StatelessWidget {
  const SalesDashboardContent({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Expanded(
              child: Text(
                'Sales overview',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            SalesActionButton(
              label: 'Select date range',
              icon: Icons.calendar_today,
            ),
            SizedBox(width: 8),
            SalesActionButton(label: 'Export report', icon: Icons.download),
          ],
        ),
        SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: DashboardMockData.salesMetrics
              .map(
                (metric) => SizedBox(
                  width: 190,
                  child: SalesMetricCard(
                    label: metric.label,
                    value: metric.value,
                  ),
                ),
              )
              .toList(),
        ),
        SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: const SalesSection(
                title: 'Sales trend',
                child: SizedBox(
                  height: 220,
                  child: Center(child: Text('Sales trend chart')),
                ),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: const SalesSection(
                title: 'Sales by category',
                child: SizedBox(
                  height: 220,
                  child: Center(child: Text('Sales by category chart')),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        SalesSection(
          title: 'Recent transactions',
          actionLabel: 'View all',
          child: SalesDataTable(
            columns: DashboardMockData.recentTransactions.columns,
            rows: DashboardMockData.recentTransactions.rows,
          ),
        ),
      ],
    );
  }
}
