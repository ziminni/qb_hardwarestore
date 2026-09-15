import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/suppliers/widgets/purchases_status_badge.dart';
import 'package:flutter/material.dart';

class PurchasesDetailsDialog extends StatelessWidget {
  const PurchasesDetailsDialog({super.key, required this.order});
  final PurchaseOrder order;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('PO-${order.id}'),
    content: SizedBox(
      width: 700,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.supplierName,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('Created by ${order.createdBy}'),
                    ],
                  ),
                ),
                PurchasesStatusBadge(status: order.status),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Notes: ${order.notes.isEmpty ? '—' : order.notes}'),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            ...order.items.map(
              (item) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${item.productName} — ${item.variantName}'),
                subtitle: Text(
                  '${item.sku} · Ordered ${item.quantity.toStringAsFixed(0)} · Received ${item.receivedQuantity.toStringAsFixed(0)}',
                ),
                trailing: Text('₱${item.subtotal.toStringAsFixed(2)}'),
              ),
            ),
            const Divider(),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total: ₱${order.total.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      FilledButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}
