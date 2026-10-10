import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/inventory_sales_status_badge.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_records_table.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SalesReturnsPage extends StatelessWidget {
  const SalesReturnsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final records = context.watch<InventorySalesViewmodel>().returns;
    return SalesSkeletonLayout(
      title: 'Returns & Refunds',
      subtitle: 'Review customer returns, replacements, and refund outcomes.',
      selectedNavigationIndex: 6,
      onNavigationSelected: (index) => navigateSales(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.assignment_return_outlined),
              label: const Text('New customer return'),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SalesRecordsTable(
            columns: const [
              'Return',
              'Date',
              'Transaction',
              'Product',
              'Quantity',
              'Reason',
              'Status',
              'Action',
            ],
            emptyMessage: 'No customer returns available.',
            rows: records
                .where((item) => item.type.name == 'customer')
                .map(
                  (item) => <Widget>[
                    Text(item.reference),
                    Text(
                      '${item.date.month}/${item.date.day}/${item.date.year}',
                    ),
                    Text(item.relatedReference),
                    Text('${item.productName} — ${item.variantName}'),
                    Text(item.quantity.toStringAsFixed(0)),
                    Text(item.reason),
                    InventorySalesStatusBadge.returnStatus(status: item.status),
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
