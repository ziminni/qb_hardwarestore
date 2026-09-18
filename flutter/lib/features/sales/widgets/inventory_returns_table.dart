import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/sales/widgets/inventory_sales_status_badge.dart';
import 'package:flutter/material.dart';

class InventoryReturnsTable extends StatelessWidget {
  const InventoryReturnsTable({super.key, required this.returns});
  final List<InventoryReturn> returns;
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
      child: returns.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: Text('No returns match these filters.')),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  colors.secondaryContainer,
                ),
                columns: const [
                  DataColumn(label: Text('Reference')),
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Type')),
                  DataColumn(label: Text('Related To')),
                  DataColumn(label: Text('Product')),
                  DataColumn(label: Text('Variant')),
                  DataColumn(label: Text('SKU')),
                  DataColumn(label: Text('Quantity')),
                  DataColumn(label: Text('Reason')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Processed By')),
                ],
                rows: returns
                    .map(
                      (item) => DataRow(
                        cells: [
                          DataCell(
                            Text(
                              item.reference,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${item.date.year}-${item.date.month.toString().padLeft(2, '0')}-${item.date.day.toString().padLeft(2, '0')}',
                            ),
                          ),
                          DataCell(Text(item.type.label)),
                          DataCell(Text(item.relatedReference)),
                          DataCell(Text(item.productName)),
                          DataCell(Text(item.variantName)),
                          DataCell(Text(item.sku)),
                          DataCell(Text(item.quantity.toStringAsFixed(0))),
                          DataCell(
                            SizedBox(
                              width: 180,
                              child: Text(
                                item.reason,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            InventorySalesStatusBadge.returnStatus(
                              status: item.status,
                            ),
                          ),
                          DataCell(Text(item.processedBy)),
                        ],
                      ),
                    )
                    .toList(),
              ),
            ),
    );
  }
}
