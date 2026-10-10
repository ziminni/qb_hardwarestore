import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_records_table.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SalesCustomersPage extends StatefulWidget {
  const SalesCustomersPage({super.key});
  @override
  State<SalesCustomersPage> createState() => _SalesCustomersPageState();
}

class _SalesCustomersPageState extends State<SalesCustomersPage> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final customers = context
        .watch<SalesModuleViewmodel>()
        .customers
        .where(
          (item) => '${item.name} ${item.contact} ${item.type}'
              .toLowerCase()
              .contains(query.toLowerCase()),
        )
        .toList();
    return SalesSkeletonLayout(
      title: 'Customers',
      subtitle: 'Manage customer profiles and sales relationships.',
      selectedNavigationIndex: 4,
      onNavigationSelected: (index) => navigateSales(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  width: 360,
                  child: TextField(
                    onChanged: (value) => setState(() => query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search customers',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.person_add_outlined),
                label: const Text('Add customer'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          SalesRecordsTable(
            columns: const [
              'Customer ID',
              'Name',
              'Contact',
              'Type',
              'Transactions',
              'Total Spent',
              'Action',
            ],
            emptyMessage: 'No customers match your search.',
            rows: customers
                .map(
                  (item) => <Widget>[
                    Text(item.id),
                    Text(item.name),
                    Text(item.contact),
                    Text(item.type),
                    Text('${item.transactions}'),
                    Text('₱${item.totalSpent.toStringAsFixed(2)}'),
                    TextButton(onPressed: () {}, child: const Text('Profile')),
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
