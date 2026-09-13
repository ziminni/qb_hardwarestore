import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_movements_table.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class InventoryStockMovementsPage extends StatefulWidget {
  const InventoryStockMovementsPage({super.key});
  @override
  State<InventoryStockMovementsPage> createState() =>
      _InventoryStockMovementsPageState();
}

class _InventoryStockMovementsPageState
    extends State<InventoryStockMovementsPage> {
  String _query = '';
  InventoryMovementType? _type;
  bool _newestFirst = true;
  int _page = 1;
  int _rows = 10;

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    final filtered =
        inventory.movements.where((movement) {
          final product = inventory.products.firstWhere(
            (item) => item.id == movement.productId,
          );
          final variant = product.variants.firstWhere(
            (item) => item.id == movement.variantId,
          );
          final text =
              '${product.baseName} ${variant.variantName} ${variant.sku} ${movement.reference} ${movement.reason}'
                  .toLowerCase();
          return text.contains(_query.toLowerCase()) &&
              (_type == null || movement.type == _type);
        }).toList()..sort(
          (a, b) => _newestFirst
              ? b.timestamp.compareTo(a.timestamp)
              : a.timestamp.compareTo(b.timestamp),
        );
    final pages = (filtered.length / _rows).ceil().clamp(1, 999);
    _page = _page.clamp(1, pages);
    final start = (_page - 1) * _rows;
    final visible = filtered.skip(start).take(_rows).toList();
    return InventorySkeletonLayout(
      title: 'Stock Movements',
      subtitle: 'See when, why, and by how much inventory changed.',
      selectedNavigationIndex: 4,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SizedBox(
                width: 300,
                child: TextField(
                  onChanged: (value) => setState(() {
                    _query = value;
                    _page = 1;
                  }),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search movements',
                  ),
                ),
              ),
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<InventoryMovementType?>(
                  initialValue: _type,
                  decoration: const InputDecoration(labelText: 'Movement type'),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('All movement types'),
                    ),
                    ...InventoryMovementType.values.map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(item.label),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _type = value;
                    _page = 1;
                  }),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() => _newestFirst = !_newestFirst),
                icon: const Icon(Icons.sort),
                label: Text(_newestFirst ? 'Newest first' : 'Oldest first'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          InventoryMovementsTable(
            movements: visible,
            products: inventory.products,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '${filtered.isEmpty ? 0 : start + 1}–${start + visible.length} of ${filtered.length}',
              ),
              const SizedBox(width: AppSpacing.md),
              DropdownButton<int>(
                value: _rows,
                items: const [10, 20, 30]
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text('$value rows'),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() {
                  _rows = value ?? 10;
                  _page = 1;
                }),
              ),
              IconButton(
                onPressed: _page > 1 ? () => setState(() => _page--) : null,
                icon: const Icon(Icons.chevron_left),
              ),
              Text('$_page of $pages'),
              IconButton(
                onPressed: _page < pages ? () => setState(() => _page++) : null,
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
