import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/suppliers/widgets/purchases_status_badge.dart';
import 'package:flutter/material.dart';

/// The purchase-order book, with the two transitions the server allows.
///
/// Which action is offered is decided by the ORDER's status, because the server
/// is strict about it: `place/` only leaves DRAFT (`INVALID_PO_STATE` otherwise)
/// and `cancel/` refuses an order with goods already received
/// (`PO_HAS_RECEIPTS`). A button that could only produce a refusal is not
/// rendered at all — the disabled/live distinction is the viewmodel's `canPlace`
/// / `canCancel` (Phase 4 Task 4).
class PurchasesTable extends StatelessWidget {
  const PurchasesTable({
    super.key,
    required this.orders,
    required this.onView,
    required this.onPlace,
    required this.onCancel,
  });
  final List<PurchaseOrder> orders;
  final ValueChanged<PurchaseOrder> onView;
  final ValueChanged<PurchaseOrder> onPlace;
  final ValueChanged<PurchaseOrder> onCancel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    String date(DateTime? value) => value == null ? '—' : formatDate(value);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      clipBehavior: Clip.antiAlias,
      child: orders.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(48),
              child: Center(
                child: Text('No purchase orders match these filters.'),
              ),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStatePropertyAll(
                  colors.secondaryContainer,
                ),
                columns: const [
                  DataColumn(label: Text('PO Number')),
                  DataColumn(label: Text('Supplier')),
                  DataColumn(label: Text('Order Date')),
                  DataColumn(label: Text('Expected Delivery')),
                  DataColumn(label: Text('Items')),
                  DataColumn(label: Text('Received')),
                  DataColumn(label: Text('Total')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: orders
                    .map(
                      (order) => DataRow(
                        cells: [
                          DataCell(
                            Text(
                              'PO-${order.id}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          DataCell(Text(order.supplierName)),
                          DataCell(Text(date(order.orderDate))),
                          DataCell(Text(date(order.expectedDelivery))),
                          DataCell(Text('${order.items.length}')),
                          DataCell(
                            Text(
                              '${order.receivedQuantity.toStringAsFixed(0)} / ${order.orderedQuantity.toStringAsFixed(0)}',
                            ),
                          ),
                          DataCell(Text(formatPeso(order.total))),
                          DataCell(PurchasesStatusBadge(status: order.status)),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'View purchase order',
                                  onPressed: () => onView(order),
                                  icon: const Icon(
                                    Icons.visibility_outlined,
                                    size: 18,
                                  ),
                                ),
                                if (order.canPlace)
                                  IconButton(
                                    tooltip: 'Place purchase order',
                                    onPressed: () => onPlace(order),
                                    icon: const Icon(
                                      Icons.send_outlined,
                                      size: 18,
                                    ),
                                  ),
                                if (order.canCancel)
                                  IconButton(
                                    tooltip: 'Cancel purchase order',
                                    onPressed: () => onCancel(order),
                                    icon: const Icon(
                                      Icons.block_outlined,
                                      size: 18,
                                    ),
                                  ),
                              ],
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
