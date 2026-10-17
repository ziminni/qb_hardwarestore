import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/inventory_return_form_dialog.dart';
import 'package:client/features/sales/widgets/inventory_returns_table.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class InventoryReturnsPage extends StatefulWidget {
  const InventoryReturnsPage({super.key});
  @override
  State<InventoryReturnsPage> createState() => _InventoryReturnsPageState();
}

class _InventoryReturnsPageState extends State<InventoryReturnsPage> {
  String _query = '';
  InventoryReturnType? _type;
  Future<void> _create() async {
    final state = context.read<InventorySalesViewmodel>();
    final result = await showDialog<InventoryReturn>(
      context: context,
      builder: (_) => InventoryReturnFormDialog(
        sales: state.sales
            .where((sale) => sale.status == InventorySaleStatus.completed)
            .toList(),
      ),
    );
    if (result == null || !mounted) return;
    state.addReturn(result);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Return recorded in mock data. Stock is unchanged until future approval integration.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<InventorySalesViewmodel>();
    final returns = state.returns
        .where(
          (item) =>
              '${item.reference} ${item.relatedReference} ${item.productName} ${item.sku}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()) &&
              (_type == null || item.type == _type),
        )
        .toList();
    return InventorySkeletonLayout(
      title: 'Returns',
      subtitle: 'Track customer and supplier returns affecting inventory.',
      selectedNavigationIndex: 9,
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
                    hintText: 'Search return, reference, or SKU',
                  ),
                ),
              ),
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<InventoryReturnType?>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Return type'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All return types'),
                    ),
                    ...InventoryReturnType.values.map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(item.label),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _type = value),
                ),
              ),
              FilledButton.icon(
                onPressed: _create,
                icon: const Icon(Icons.add),
                label: const Text('Record Return'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          InventoryReturnsTable(returns: returns),
        ],
      ),
    );
  }
}
