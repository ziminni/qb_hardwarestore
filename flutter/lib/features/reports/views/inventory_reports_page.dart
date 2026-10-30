import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/reports/widgets/inventory_report_metric_card.dart';
import 'package:client/features/reports/widgets/inventory_top_products_table.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/shared/widgets/section_heading.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class InventoryReportsPage extends StatelessWidget {
  const InventoryReportsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final sales = context.watch<InventorySalesViewmodel>();
    final inventory = context.watch<InventoryViewmodel>();
    final completed = sales.sales
        .where((item) => item.status.name == 'completed')
        .toList();
    final lines = completed.expand((item) => item.lines).toList();
    final lowStock = inventory.stockRecords
        .where((item) => inventory.statusFor(item.variant).name != 'inStock')
        .length;
    return InventorySkeletonLayout(
      title: 'Reports',
      subtitle: 'Inventory-facing sales, returns, and stock indicators.',
      selectedNavigationIndex: 10,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = AppSpacing.md;
              final columns = constraints.maxWidth >= 980
                  ? 4
                  : constraints.maxWidth >= 520
                  ? 2
                  : 1;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  SizedBox(
                    width: width,
                    child: InventoryReportMetricCard(
                      label: 'Completed sales value',
                      value: '₱${sales.completedRevenue.toStringAsFixed(2)}',
                      icon: Icons.payments_outlined,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: InventoryReportMetricCard(
                      label: 'Units sold',
                      value: sales.soldUnits.toStringAsFixed(0),
                      icon: Icons.shopping_cart_outlined,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: InventoryReportMetricCard(
                      label: 'Return records',
                      value: '${sales.returns.length}',
                      icon: Icons.undo_rounded,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: InventoryReportMetricCard(
                      label: 'Low/out of stock',
                      value: '$lowStock',
                      icon: Icons.warning_amber_rounded,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          SectionHeading(
            title: 'Sales performance',
            subtitle: 'Which products move the most value through inventory',
            trailing: [
              OutlinedButton.icon(
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Export will be connected in a future implementation.',
                    ),
                  ),
                ),
                icon: const Icon(Icons.download_outlined),
                label: const Text('Export Report'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          InventoryTopProductsTable(lines: lines),
        ],
      ),
    );
  }
}
