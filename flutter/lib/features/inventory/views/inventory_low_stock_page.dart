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

    // Decision 13, rule 1: the low-stock screen READS the server's alerts. It no
    // longer decides for itself which variants are low.
    //
    // Membership therefore comes from `alerts`; the product/variant pairing still
    // comes from `stockRecords`, which Phase 1 made API-backed. That keeps the
    // authority with the server while the table keeps the shape it renders.
    //
    // The visible consequence, accepted in the decision: a variant below its
    // threshold WITHOUT a server alert does not appear here. Before, the client's
    // own predicate decided and could disagree with the alert screen.
    final alertedVariantIds = inventory.alerts
        .where((alert) => !alert.isResolved)
        .map((alert) => alert.variantId)
        .toSet();
    final records = inventory.stockRecords
        .where(
          (record) =>
              alertedVariantIds.contains(record.variant.id) &&
              '${record.product.baseName} ${record.variant.variantName} ${record.variant.barcode}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
        )
        .toList();
    return InventorySkeletonLayout(
      title: 'Low Stock',
      // Was "Variants at or below their reorder level", which described the
      // derivation this screen no longer does.
      subtitle: 'Variants the server has alerted as low or out of stock.',
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
