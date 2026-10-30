import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/suppliers/widgets/purchases_status_badge.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';

class PurchasesDetailsDialog extends StatelessWidget {
  const PurchasesDetailsDialog({super.key, required this.order});
  final PurchaseOrder order;
  @override
  Widget build(BuildContext context) => AppDialog(
    icon: Icons.receipt_long_outlined,
    title: 'PO-${order.id}',
    subtitle: order.supplierName,
    headerTrailing: PurchasesStatusBadge(status: order.status),
    width: 720,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailRow(label: 'Supplier', value: order.supplierName),
        DetailRow(label: 'Created by', value: order.createdBy),
        DetailRow(
          label: 'Received',
          value:
              '${order.receivedQuantity.toStringAsFixed(0)} / ${order.orderedQuantity.toStringAsFixed(0)} units',
        ),
        DetailRow(
          label: 'Notes',
          value: order.notes.isEmpty ? '—' : order.notes,
        ),
        const SizedBox(height: AppSpacing.xl),
        DialogSectionLabel('Items (${order.items.length})'),
        ...order.items.map(
          (item) => LineItemTile(
            title: '${item.productName} — ${item.variantName}',
            subtitle:
                '${item.sku} · Ordered ${item.quantity.toStringAsFixed(0)} · Received ${item.receivedQuantity.toStringAsFixed(0)}',
            amount: '₱${item.subtotal.toStringAsFixed(2)}',
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TotalBar(
          label: 'Order total',
          value: '₱${order.total.toStringAsFixed(2)}',
        ),
      ],
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
