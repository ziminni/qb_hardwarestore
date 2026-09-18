import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/sales/widgets/inventory_sales_status_badge.dart';
import 'package:flutter/material.dart';

class InventorySalesTable extends StatelessWidget {
  const InventorySalesTable({
    super.key,
    required this.sales,
    required this.onView,
  });
  final List<InventorySale> sales;
  final ValueChanged<InventorySale> onView;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: sales.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: Text('No sales match these filters.')),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  colors.secondaryContainer,
                ),
                columns: const [
                  DataColumn(label: Text('Transaction')),
                  DataColumn(label: Text('Date / Time')),
                  DataColumn(label: Text('Customer')),
                  DataColumn(label: Text('Source')),
                  DataColumn(label: Text('Items')),
                  DataColumn(label: Text('Units')),
                  DataColumn(label: Text('Total')),
                  DataColumn(label: Text('Payment')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Action')),
                ],
                rows: sales
                    .map(
                      (sale) => DataRow(
                        cells: [
                          DataCell(
                            Text(
                              sale.transactionNo,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${sale.date.year}-${sale.date.month.toString().padLeft(2, '0')}-${sale.date.day.toString().padLeft(2, '0')} ${sale.date.hour.toString().padLeft(2, '0')}:${sale.date.minute.toString().padLeft(2, '0')}',
                            ),
                          ),
                          DataCell(Text(sale.customer)),
                          DataCell(Text(sale.source)),
                          DataCell(Text('${sale.lines.length}')),
                          DataCell(Text(sale.totalQuantity.toStringAsFixed(0))),
                          DataCell(Text('₱${sale.total.toStringAsFixed(2)}')),
                          DataCell(Text(sale.paymentMethod)),
                          DataCell(
                            InventorySalesStatusBadge.sale(status: sale.status),
                          ),
                          DataCell(
                            IconButton(
                              onPressed: () => onView(sale),
                              icon: const Icon(
                                Icons.visibility_outlined,
                                size: 18,
                              ),
                              tooltip: 'View sale',
                            ),
                          ),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
    );
  }
}
