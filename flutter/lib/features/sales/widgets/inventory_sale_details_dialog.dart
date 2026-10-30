import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/sales/widgets/inventory_sales_status_badge.dart';
import 'package:client/shared/widgets/app_dialog.dart';
import 'package:flutter/material.dart';

class InventorySaleDetailsDialog extends StatelessWidget {
  const InventorySaleDetailsDialog({super.key, required this.sale});
  final InventorySale sale;
  @override
  Widget build(BuildContext context) => AppDialog(
    icon: Icons.point_of_sale_outlined,
    title: sale.transactionNo,
    subtitle: sale.customer,
    headerTrailing: InventorySalesStatusBadge.sale(status: sale.status),
    width: 700,
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DetailRow(label: 'Customer', value: sale.customer),
        DetailRow(label: 'Source', value: sale.source),
        DetailRow(label: 'Payment', value: sale.paymentMethod),
        DetailRow(label: 'Cashier', value: sale.cashier),
        const SizedBox(height: AppSpacing.xl),
        DialogSectionLabel('Items (${sale.lines.length})'),
        ...sale.lines.map(
          (line) => LineItemTile(
            title: '${line.productName} — ${line.variantName}',
            subtitle:
                '${line.sku} · ${line.quantity.toStringAsFixed(0)} × ₱${line.unitPrice.toStringAsFixed(2)}',
            amount: '₱${line.subtotal.toStringAsFixed(2)}',
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TotalBar(
          label: 'Sale total',
          value: '₱${sale.total.toStringAsFixed(2)}',
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
