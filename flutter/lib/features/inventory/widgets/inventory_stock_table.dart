import 'package:client/data/models/product.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_stock_status_badge.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:flutter/material.dart';

class InventoryStockTable extends StatelessWidget {
  const InventoryStockTable({
    super.key,
    required this.records,
    required this.inventory,
    required this.onAdjust,
  });
  final List<({Product product, ProductVariant variant})> records;
  final InventoryViewmodel inventory;
  final void Function(Product product, ProductVariant variant) onAdjust;

  @override
  Widget build(BuildContext context) {
    return DataPanel(
      title: 'Stock on hand',
      subtitle: 'Live quantity per variant against its reorder level',
      count: records.length,
      isEmpty: records.isEmpty,
      emptyIcon: Icons.warehouse_outlined,
      emptyTitle: 'No stock records found',
      emptyMessage: 'No stock records match these filters.',
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Product')),
          DataColumn(label: Text('Variant')),
          DataColumn(label: Text('SKU')),
          DataColumn(label: Text('Category')),
          DataColumn(label: Text('Unit')),
          DataColumn(label: Text('Current Stock')),
          DataColumn(label: Text('Reorder Level')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Location')),
          DataColumn(label: Text('Actions')),
        ],
        rows: records
            .map(
              (record) => DataRow(
                cells: [
                  DataCell(
                    Text(
                      record.product.baseName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataCell(Text(record.variant.variantName)),
                  DataCell(Text(record.variant.sku)),
                  DataCell(Text(record.product.categoryName)),
                  DataCell(Text(record.variant.baseUomCode)),
                  DataCell(
                    Text(record.variant.currentStock.toStringAsFixed(0)),
                  ),
                  DataCell(
                    Text(record.variant.reorderLevel.toStringAsFixed(0)),
                  ),
                  DataCell(
                    InventoryStockStatusBadge(
                      status: inventory.statusFor(record.variant),
                    ),
                  ),
                  DataCell(Text(record.variant.storageLocation)),
                  DataCell(
                    OutlinedButton.icon(
                      onPressed: () => onAdjust(record.product, record.variant),
                      icon: const Icon(Icons.tune, size: 16),
                      label: const Text('Adjust Stock'),
                    ),
                  ),
                ],
              ),
            )
            .toList(),
      ),
    );
  }
}
