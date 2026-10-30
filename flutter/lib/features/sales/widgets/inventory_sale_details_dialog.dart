import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
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
                  '${line.sku} · ${line.quantity.toStringAsFixed(0)} × ${formatPeso(line.unitPrice)}',
                ),
                trailing: Text(formatPeso(line.subtotal)),
              ),
            ),
            const Divider(),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Total: ${formatPeso(sale.total)}',
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
