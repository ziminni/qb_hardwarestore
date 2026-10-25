import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_stock_status_badge.dart';
import 'package:flutter/material.dart';

/// One alert about one variant, with the catalogue rows it names.
///
/// The ALERT is the row's identity, not the variant: the same variant can carry
/// a LOW_STOCK row and an OUT_OF_STOCK row at once (the server escalates without
/// closing the older one), and each is resolved separately.
class LowStockRow {
  const LowStockRow({
    required this.alert,
    required this.product,
    required this.variant,
  });

  final SystemAlert alert;
  final Product product;
  final ProductVariant variant;
}

class InventoryLowStockTable extends StatelessWidget {
  const InventoryLowStockTable({
    super.key,
    required this.rows,
    required this.inventory,
    required this.onReorder,
    required this.onResolve,
  });
  final List<LowStockRow> rows;
  final InventoryViewmodel inventory;
  final void Function(Product product, ProductVariant variant) onReorder;

  /// Null when the caller may not resolve alerts (the Stock Manager and Admin
  /// are the only roles the server admits). A null callback removes the button
  /// rather than rendering one that would answer 403.
  final void Function(SystemAlert alert)? onResolve;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    String time(DateTime? value) => value == null
        ? '—'
        : '${value.year}-${value.month.toString().padLeft(2, '0')}-'
              '${value.day.toString().padLeft(2, '0')} '
              '${value.hour.toString().padLeft(2, '0')}:'
              '${value.minute.toString().padLeft(2, '0')}';
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: rows.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(48),
              child: Center(
                child: Text('No low-stock products match this search.'),
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
                  DataColumn(label: Text('Variant')),
                  DataColumn(label: Text('Alert')),
                  DataColumn(label: Text('Current')),
                  DataColumn(label: Text('Reorder Level')),
                  DataColumn(label: Text('Shortage')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Location')),
                  DataColumn(label: Text('Suggested Reorder')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: rows.map((row) {
                  final stock = inventory.stockOnHandFor(row.variant.id);
                  final threshold = row.variant.minStockThreshold;
                  final shortage = (threshold - stock).clamp(
                    0,
                    double.infinity,
                  );
                  final suggested = inventory.suggestedReorderQty(
                    row.variant.id,
                  );
                  final alert = row.alert;
                  return DataRow(
                    cells: [
                      DataCell(
                        Text(
                          row.product.baseName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      DataCell(Text(row.variant.variantName)),
                      DataCell(
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(alert.type.displayName),
                            if (alert.isResolved)
                              Text(
                                'Resolved by '
                                '${alert.resolvedByName.isEmpty ? 'a manager' : alert.resolvedByName}'
                                ' · ${time(alert.resolvedAt)}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                          ],
                        ),
                      ),
                      DataCell(Text(stock.toStringAsFixed(0))),
                      DataCell(Text(threshold.toStringAsFixed(0))),
                      DataCell(Text(shortage.toStringAsFixed(0))),
                      DataCell(
                        InventoryStockStatusBadge(
                          status: inventory.statusForVariant(row.variant.id),
                        ),
                      ),
                      DataCell(Text(inventory.locationHintFor(row.variant.id))),
                      DataCell(Text(suggested.toStringAsFixed(0))),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OutlinedButton(
                              onPressed: () =>
                                  onReorder(row.product, row.variant),
                              child: const Text('Reorder'),
                            ),
                            if (!alert.isResolved && onResolve != null) ...[
                              const SizedBox(width: 8),
                              TextButton(
                                onPressed: () => onResolve!(alert),
                                child: const Text('Resolve'),
                              ),
                            ],
                          ],
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
