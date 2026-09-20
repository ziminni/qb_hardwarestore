import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/inventory/widgets/inventory_stock_status_badge.dart';
import 'package:flutter/material.dart';

typedef InventoryBalanceRecord = ({
  Product product,
  ProductVariant variant,
  double opening,
  double stockIn,
  double stockOut,
  double closing,
  InventoryStockStatus status,
});

class InventoryStockBalanceTable extends StatelessWidget {
  const InventoryStockBalanceTable({
    super.key,
    required this.records,
    required this.onViewHistory,
  });

  final List<InventoryBalanceRecord> records;
  final void Function(Product product, ProductVariant variant) onViewHistory;

  String _quantity(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

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
      child: records.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(48),
              child: Center(
                child: Text(
                  'No stock activity is available for these filters.',
                ),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  colors.secondaryContainer,
                ),
                columns: const [
                  DataColumn(label: Text('Product')),
                  DataColumn(label: Text('SKU')),
                  DataColumn(label: Text('Unit')),
                  DataColumn(label: Text('Opening')),
                  DataColumn(label: Text('Stock In')),
                  DataColumn(label: Text('Stock Out')),
                  DataColumn(label: Text('Closing')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: records.map((record) {
                  final unit = record.variant.baseUomCode;
                  return DataRow(
                    cells: [
                      DataCell(
                        SizedBox(
                          width: 210,
                          child: Text(
                            '${record.product.baseName}\n${record.variant.variantName}',
                          ),
                        ),
                      ),
                      DataCell(Text(record.variant.sku)),
                      DataCell(Text(unit)),
                      DataCell(Text('${_quantity(record.opening)} $unit')),
                      DataCell(
                        Text(
                          '+${_quantity(record.stockIn)} $unit',
                          style: const TextStyle(color: AppColors.success),
                        ),
                      ),
                      DataCell(
                        Text(
                          '-${_quantity(record.stockOut)} $unit',
                          style: const TextStyle(color: AppColors.error),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${_quantity(record.closing)} $unit',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      DataCell(
                        InventoryStockStatusBadge(status: record.status),
                      ),
                      DataCell(
                        TextButton(
                          onPressed: () =>
                              onViewHistory(record.product, record.variant),
                          child: const Text('View history'),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }
}
