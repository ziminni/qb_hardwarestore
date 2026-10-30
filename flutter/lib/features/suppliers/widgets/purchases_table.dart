import 'package:client/data/models/supplier.dart';
import 'package:client/features/suppliers/widgets/purchases_status_badge.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:flutter/material.dart';

class PurchasesTable extends StatelessWidget {
  const PurchasesTable({super.key, required this.orders, required this.onView});
  final List<PurchaseOrder> orders;
  final ValueChanged<PurchaseOrder> onView;
  @override
  Widget build(BuildContext context) {
    String date(DateTime? value) => value == null
        ? '—'
        : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
    return DataPanel(
      title: 'Purchase orders',
      subtitle: 'Orders placed with suppliers and their receiving progress',
      count: orders.length,
      isEmpty: orders.isEmpty,
      emptyIcon: Icons.shopping_bag_outlined,
      emptyTitle: 'No purchase orders found',
      emptyMessage: 'No purchase orders match these filters.',
      child: DataTable(
        columns: const [
          DataColumn(label: Text('PO Number')),
          DataColumn(label: Text('Supplier')),
          DataColumn(label: Text('Order Date')),
          DataColumn(label: Text('Expected Delivery')),
          DataColumn(label: Text('Items')),
          DataColumn(label: Text('Received')),
          DataColumn(label: Text('Total')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: orders
            .map(
              (order) => DataRow(
                cells: [
                  DataCell(
                    Text(
                      'PO-${order.id}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  DataCell(Text(order.supplierName)),
                  DataCell(Text(date(order.orderDate))),
                  DataCell(Text(date(order.expectedDelivery))),
                  DataCell(Text('${order.items.length}')),
                  DataCell(
                    Text(
                      '${order.receivedQuantity.toStringAsFixed(0)} / ${order.orderedQuantity.toStringAsFixed(0)}',
                    ),
                  ),
                  DataCell(Text('₱${order.total.toStringAsFixed(2)}')),
                  DataCell(PurchasesStatusBadge(status: order.status)),
                  DataCell(
                    IconButton(
                      tooltip: 'View purchase order',
                      onPressed: () => onView(order),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
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
