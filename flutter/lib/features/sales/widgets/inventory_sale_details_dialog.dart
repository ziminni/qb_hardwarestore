import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/sales/widgets/inventory_sales_status_badge.dart';
import 'package:flutter/material.dart';

class InventorySaleDetailsDialog extends StatelessWidget {
  const InventorySaleDetailsDialog({super.key, required this.sale});
  final InventorySale sale;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(sale.transactionNo),
    content: SizedBox(
      width: 680,
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
                        sale.customer,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${sale.source} · ${sale.paymentMethod} · ${sale.cashier}',
                      ),
                    ],
                  ),
                ),
                InventorySalesStatusBadge.sale(status: sale.status),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            ...sale.lines.map(
              (line) => ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${line.productName} — ${line.variantName}'),
                subtitle: Text(
                  '${line.sku} · ${line.quantity.toStringAsFixed(0)} × ₱${line.unitPrice.toStringAsFixed(2)}',
                ),
                trailing: Text('₱${line.subtotal.toStringAsFixed(2)}'),
              ),
            ),
            const Divider(),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total: ₱${sale.total.toStringAsFixed(2)}',
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
