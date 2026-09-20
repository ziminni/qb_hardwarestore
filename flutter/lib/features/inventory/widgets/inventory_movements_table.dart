import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/product.dart';
import 'package:client/features/inventory/widgets/inventory_movement_badge.dart';
import 'package:flutter/material.dart';

class InventoryMovementsTable extends StatelessWidget {
  const InventoryMovementsTable({
    super.key,
    required this.movements,
    required this.products,
    required this.onView,
    required this.emptyMessage,
  });
  final List<InventoryMovement> movements;
  final List<Product> products;
  final ValueChanged<InventoryMovement> onView;
  final String emptyMessage;
  ({Product product, ProductVariant variant}) _record(
    InventoryMovement movement,
  ) {
    final product = products.firstWhere(
      (item) => item.id == movement.productId,
    );
    return (
      product: product,
      variant: product.variants.firstWhere(
        (item) => item.id == movement.variantId,
      ),
    );
  }

  String _number(double value) {
    final number = value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(2);
    return '${value > 0 ? '+' : ''}$number';
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
      child: movements.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(48),
              child: Center(child: Text(emptyMessage)),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  colors.secondaryContainer,
                ),
                columns: const [
                  DataColumn(label: Text('Date / Time')),
                  DataColumn(label: Text('Product')),
                  DataColumn(label: Text('Variant')),
                  DataColumn(label: Text('SKU')),
                  DataColumn(label: Text('Movement Type')),
                  DataColumn(label: Text('Change')),
                  DataColumn(label: Text('Previous')),
                  DataColumn(label: Text('New')),
                  DataColumn(label: Text('Reference')),
                  DataColumn(label: Text('Reason')),
                  DataColumn(label: Text('User')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: movements.map((movement) {
                  final record = _record(movement);
                  final unit = movement.unit ?? record.variant.baseUomCode;
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          '${movement.timestamp.year}-${movement.timestamp.month.toString().padLeft(2, '0')}-${movement.timestamp.day.toString().padLeft(2, '0')} ${movement.timestamp.hour.toString().padLeft(2, '0')}:${movement.timestamp.minute.toString().padLeft(2, '0')}',
                        ),
                      ),
                      DataCell(Text(record.product.baseName)),
                      DataCell(Text(record.variant.variantName)),
                      DataCell(Text(record.variant.sku)),
                      DataCell(InventoryMovementBadge(type: movement.type)),
                      DataCell(
                        Text(
                          '${_number(movement.quantityChange)} $unit',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: movement.quantityChange >= 0
                                ? AppColors.success
                                : AppColors.error,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${_number(movement.previousStock).replaceFirst('+', '')} $unit',
                        ),
                      ),
                      DataCell(
                        Text(
                          '${_number(movement.newStock).replaceFirst('+', '')} $unit',
                        ),
                      ),
                      DataCell(Text(movement.reference)),
                      DataCell(
                        SizedBox(
                          width: 220,
                          child: Text(
                            movement.reason,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text(movement.userName)),
                      DataCell(
                        TextButton(
                          onPressed: () => onView(movement),
                          child: const Text('View'),
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
