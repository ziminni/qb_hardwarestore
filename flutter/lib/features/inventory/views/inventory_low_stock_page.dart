import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_low_stock_table.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class InventoryLowStockPage extends StatefulWidget {
  const InventoryLowStockPage({super.key});
  @override
  State<InventoryLowStockPage> createState() => _InventoryLowStockPageState();
}

class _InventoryLowStockPageState extends State<InventoryLowStockPage> {
  String _query = '';
  void _reorder(Product product, ProductVariant variant) => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Future Purchasing connection'),
      content: Text(
        'Reordering ${product.baseName} — ${variant.variantName} will connect to the Purchasing module in a future implementation.',
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Understood'),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    final records = inventory.stockRecords
        .where(
          (record) =>
              inventory.statusFor(record.variant).name != 'inStock' &&
              '${record.product.baseName} ${record.variant.variantName} ${record.variant.sku}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
        )
        .toList();
    return InventorySkeletonLayout(
      title: 'Low Stock',
      subtitle: 'Variants at or below their reorder level.',
      selectedNavigationIndex: 5,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 340,
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search low-stock items',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          InventoryLowStockTable(
            records: records,
            inventory: inventory,
            onReorder: _reorder,
          ),
        ],
      ),
    );
  }
}
