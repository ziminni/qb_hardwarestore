import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/data/models/sales.dart';
import 'package:flutter/material.dart';

class InventoryTopProductsTable extends StatelessWidget {
  const InventoryTopProductsTable({super.key, required this.lines});
  final List<InventorySaleLine> lines;
  @override
  Widget build(BuildContext context) {
    final totals =
        <
          String,
          ({String variant, String sku, double quantity, double revenue})
        >{};
    for (final line in lines) {
      final old = totals[line.productName];
      totals[line.productName] = (
        variant: line.variantName,
        sku: line.sku,
        quantity: (old?.quantity ?? 0) + line.quantity,
        revenue: (old?.revenue ?? 0) + line.subtotal,
      );
    }
    final rows = totals.entries.toList()
      ..sort((a, b) => b.value.revenue.compareTo(a.value.revenue));
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(colors.secondaryContainer),
          columns: const [
            DataColumn(label: Text('Product')),
            DataColumn(label: Text('Top Variant')),
            DataColumn(label: Text('SKU')),
            DataColumn(label: Text('Units Sold')),
            DataColumn(label: Text('Sales Value')),
          ],
          rows: rows
              .map(
                (row) => DataRow(
                  cells: [
                    DataCell(
                      Text(
                        row.key,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    DataCell(Text(row.value.variant)),
                    DataCell(Text(row.value.sku)),
                    DataCell(Text(row.value.quantity.toStringAsFixed(0))),
                    DataCell(Text('₱${row.value.revenue.toStringAsFixed(2)}')),
                  ],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
