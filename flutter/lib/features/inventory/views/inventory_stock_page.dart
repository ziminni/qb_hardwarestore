import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_adjust_stock_dialog.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/inventory/widgets/inventory_stock_table.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class InventoryStockPage extends StatefulWidget {
  const InventoryStockPage({super.key});
  @override
  State<InventoryStockPage> createState() => _InventoryStockPageState();
}

class _InventoryStockPageState extends State<InventoryStockPage> {
  String _query = '';
  String? _category;
  InventoryStockStatus? _status;
  String? _location;
  bool _ascending = true;

  Future<void> _adjust(Product product, ProductVariant variant) async {
    final result = await showDialog<InventoryAdjustStockResult>(
      context: context,
      builder: (_) =>
          InventoryAdjustStockDialog(product: product, variant: variant),
    );
    if (result == null || !mounted) return;
    final inventory = context.read<InventoryViewmodel>();
    final user =
        context.read<AuthViewmodel>().user?.fullName ?? 'Inventory Staff';
    inventory.adjustStock(
      variantId: variant.id,
      newQuantity: result.quantity,
      reason: result.reason,
      notes: result.notes,
      userName: user,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Stock and movement history updated in mock data.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    final locations =
        inventory.stockRecords
            .map((item) => item.variant.storageLocation)
            .toSet()
            .toList()
          ..sort();
    final records =
        inventory.stockRecords.where((record) {
          final search =
              '${record.product.baseName} ${record.variant.variantName} ${record.variant.sku}'
                  .toLowerCase();
          return search.contains(_query.toLowerCase()) &&
              (_category == null || record.product.categoryName == _category) &&
              (_status == null ||
                  inventory.statusFor(record.variant) == _status) &&
              (_location == null ||
                  record.variant.storageLocation == _location);
        }).toList()..sort(
          (a, b) => _ascending
              ? a.product.baseName.compareTo(b.product.baseName)
              : b.product.baseName.compareTo(a.product.baseName),
        );
    return InventorySkeletonLayout(
      title: 'Stock',
      subtitle: 'Current quantity for every product variant.',
      selectedNavigationIndex: 3,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SizedBox(
                width: 280,
                child: TextField(
                  onChanged: (value) => setState(() => _query = value),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search product, variant, or SKU',
                  ),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String?>(
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All categories'),
                    ),
                    ...inventory.categories.map(
                      (item) => DropdownMenuItem(
                        value: item.name,
                        child: Text(item.name),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _category = value),
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<InventoryStockStatus?>(
                  initialValue: _status,
                  decoration: const InputDecoration(labelText: 'Stock status'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All statuses'),
                    ),
                    ...InventoryStockStatus.values.map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(item.label),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _status = value),
                ),
              ),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String?>(
                  initialValue: _location,
                  decoration: const InputDecoration(labelText: 'Location'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All locations'),
                    ),
                    ...locations.map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    ),
                  ],
                  onChanged: (value) => setState(() => _location = value),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() => _ascending = !_ascending),
                icon: const Icon(Icons.sort_by_alpha),
                label: Text(_ascending ? 'Name A–Z' : 'Name Z–A'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          InventoryStockTable(
            records: records,
            inventory: inventory,
            onAdjust: _adjust,
          ),
        ],
      ),
    );
  }
}
