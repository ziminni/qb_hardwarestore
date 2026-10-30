import 'package:client/data/models/product.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_stock_status_badge.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:flutter/material.dart';

class InventoryLowStockTable extends StatelessWidget {
  const InventoryLowStockTable({
    super.key,
    required this.records,
    required this.inventory,
    required this.onReorder,
  });
  final List<({Product product, ProductVariant variant})> records;
  final InventoryViewmodel inventory;
  final void Function(Product product, ProductVariant variant) onReorder;

  @override
  Widget build(BuildContext context) {
    return DataPanel(
      title: 'Replenishment needed',
      subtitle: 'Variants at or below their reorder level',
      count: records.length,
      isEmpty: records.isEmpty,
      emptyIcon: Icons.warning_amber_rounded,
      emptyTitle: 'All stock levels are healthy',
      emptyMessage: 'No low-stock products match this search.',
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Product')),
          DataColumn(label: Text('Variant')),
          DataColumn(label: Text('SKU')),
          DataColumn(label: Text('Current')),
          DataColumn(label: Text('Reorder Level')),
          DataColumn(label: Text('Shortage')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Location')),
          DataColumn(label: Text('Suggested Reorder')),
          DataColumn(label: Text('Action')),
        ],
        rows: records.map((record) {
          final shortage =
              (record.variant.reorderLevel - record.variant.currentStock).clamp(
                0,
                double.infinity,
              );
          final suggested =
              record.variant.reorderLevel * 2 - record.variant.currentStock;
          return DataRow(
            cells: [
              DataCell(
                Text(
                  record.product.baseName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              DataCell(Text(record.variant.variantName)),
              DataCell(Text(record.variant.sku)),
              DataCell(Text(record.variant.currentStock.toStringAsFixed(0))),
              DataCell(Text(record.variant.reorderLevel.toStringAsFixed(0))),
              DataCell(Text(shortage.toStringAsFixed(0))),
              DataCell(
                InventoryStockStatusBadge(
                  status: inventory.statusFor(record.variant),
                ),
              ),
              DataCell(Text(record.variant.storageLocation)),
              DataCell(Text(suggested.toStringAsFixed(0))),
              DataCell(
                OutlinedButton(
                  onPressed: () => onReorder(record.product, record.variant),
                  child: const Text('Reorder'),
                ),
              ),
            ],
          );
        }).toList(),
      ),
    );
  }
}
