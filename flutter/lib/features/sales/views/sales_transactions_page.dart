import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/inventory_sales_status_badge.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_records_table.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SalesTransactionsPage extends StatefulWidget {
  const SalesTransactionsPage({super.key});
  @override
  State<SalesTransactionsPage> createState() => _SalesTransactionsPageState();
}

class _SalesTransactionsPageState extends State<SalesTransactionsPage> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final sales = context
        .watch<InventorySalesViewmodel>()
        .sales
        .where(
          (sale) =>
              '${sale.transactionNo} ${sale.customer} ${sale.paymentMethod}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    return SalesSkeletonLayout(
      title: 'Sales Transactions',
      subtitle: 'Review completed, refunded, and voided sales.',
      selectedNavigationIndex: 1,
      onNavigationSelected: (index) => navigateSales(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 360,
            child: TextField(
              onChanged: (value) => setState(() => query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Transaction, customer, or payment',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SalesRecordsTable(
            columns: const [
              'Transaction',
              'Date',
              'Customer',
              'Source',
              'Payment',
              'Total',
              'Status',
              'Action',
            ],
            emptyMessage: 'No sales transactions match your search.',
            rows: sales
                .map(
                  (sale) => <Widget>[
                    Text(sale.transactionNo),
                    Text(
                      '${sale.date.month}/${sale.date.day}/${sale.date.year}',
                    ),
                    Text(sale.customer),
                    Text(sale.source),
                    Text(sale.paymentMethod),
                    Text('₱${sale.total.toStringAsFixed(2)}'),
                    InventorySalesStatusBadge.sale(status: sale.status),
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
