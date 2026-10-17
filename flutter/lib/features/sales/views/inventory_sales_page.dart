import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/inventory_sale_details_dialog.dart';
import 'package:client/features/sales/widgets/inventory_sales_table.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class InventorySalesPage extends StatefulWidget {
  const InventorySalesPage({super.key});
  @override
  State<InventorySalesPage> createState() => _InventorySalesPageState();
}

class _InventorySalesPageState extends State<InventorySalesPage> {
  String _query = '';
  InventorySaleStatus? _status;
  @override
  Widget build(BuildContext context) {
    final state = context.watch<InventorySalesViewmodel>();
    final sales = state.sales
        .where(
          (sale) =>
              '${sale.transactionNo} ${sale.customer} ${sale.lines.map((line) => line.sku).join(' ')}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()) &&
              (_status == null || sale.status == _status),
        )
        .toList();
    return InventorySkeletonLayout(
      title: 'Sales',
      subtitle: 'Review inventory deducted through completed sales.',
      selectedNavigationIndex: 8,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SizedBox(
                width: 330,
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search transaction, customer, or SKU',
                  ),
                ),
              ),
              SizedBox(
                width: 190,
                child: DropdownButtonFormField<InventorySaleStatus?>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All statuses'),
                    ),
                    ...InventorySaleStatus.values.map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(item.label),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _status = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          InventorySalesTable(
            sales: sales,
            onView: (sale) => showDialog<void>(
              context: context,
              builder: (_) => InventorySaleDetailsDialog(sale: sale),
            ),
          ),
        ],
      ),
    );
  }
}
