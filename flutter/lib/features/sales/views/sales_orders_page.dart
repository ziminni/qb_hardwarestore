import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/sales_module.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_records_table.dart';
import 'package:client/features/sales/widgets/sales_status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SalesOrdersPage extends StatelessWidget {
  const SalesOrdersPage({super.key});
  @override
  Widget build(BuildContext context) {
    final records = context.watch<SalesModuleViewmodel>().orders;
    String label(SalesOrderStatus value) =>
        value.name[0].toUpperCase() + value.name.substring(1);
    String tone(SalesOrderStatus value) => switch (value) {
      SalesOrderStatus.completed => 'success',
      SalesOrderStatus.ready => 'info',
      SalesOrderStatus.processing => 'warning',
      _ => 'default',
    };
    return SalesSkeletonLayout(
      title: 'Sales Orders',
      subtitle: 'Track confirmed orders from preparation through completion.',
      selectedNavigationIndex: 3,
      onNavigationSelected: (index) => navigateSales(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('New sales order'),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SalesRecordsTable(
            columns: const [
              'Order',
              'Customer',
              'Order Date',
              'Total',
              'Status',
              'Actions',
            ],
            emptyMessage: 'No sales orders available.',
            rows: records
                .map(
                  (item) => <Widget>[
                    Text(item.number),
                    Text(item.customer),
                    Text(
                      '${item.date.month}/${item.date.day}/${item.date.year}',
                    ),
                    Text('₱${item.total.toStringAsFixed(2)}'),
                    SalesStatusBadge(
                      label: label(item.status),
                      tone: tone(item.status),
                    ),
                    TextButton(onPressed: () {}, child: const Text('View')),
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
