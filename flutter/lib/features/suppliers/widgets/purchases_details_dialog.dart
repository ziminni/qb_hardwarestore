import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
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
                // A live PO line carries only the variant name: `POItemSerializer`
                // sends no product name and no SKU (decision D-02). Joining an
                // empty product name would render " — Portland Cement 40kg" and
                // an empty SKU a leading " · ", so both are dropped when absent
                // instead of inventing a label the server never sent.
                title: Text(
                  item.productName.isEmpty
                      ? item.variantName
                      : '${item.productName} — ${item.variantName}',
                ),
                subtitle: Text(
                  [
                    if (item.sku.isNotEmpty) item.sku,
                    'Ordered ${item.quantity.toStringAsFixed(0)}',
                    'Received ${item.receivedQuantity.toStringAsFixed(0)}',
                  ].join(' · '),
                ),
                trailing: Text(formatPeso(item.subtotal)),
              ),
            ),
            const Divider(),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total: ${formatPeso(order.total)}',
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
