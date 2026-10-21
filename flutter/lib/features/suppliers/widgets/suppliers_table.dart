import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/data/models/supplier.dart';
import 'package:flutter/material.dart';

class SuppliersTable extends StatelessWidget {
  const SuppliersTable({
    super.key,
    required this.suppliers,
    required this.purchaseCount,
    required this.onEdit,
    required this.onToggle,
  });
  final List<Supplier> suppliers;
  final int Function(int supplierId) purchaseCount;

  /// Opens the edit dialog, or null when no write scope exists.
  ///
  /// D-02 scoped this pass to reads, so the page passes null and the Edit
  /// action is not rendered at all. A greyed icon or an icon that opens a
  /// dialog whose Save button cannot save would be a control that lies — the
  /// same reason `saveSupplier` was deleted from the viewmodel.
  final ValueChanged<Supplier>? onEdit;
  final ValueChanged<Supplier> onToggle;
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
      child: suppliers.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: Text('No suppliers match this search.')),
            )
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                // The Company cell is two lines (name + address). The default
                // 48px row overflows it by ~12px, so rows are given room here
                // rather than squeezed.
                dataRowMinHeight: 64,
                dataRowMaxHeight: 64,
                headingRowColor: WidgetStatePropertyAll(
                  colors.secondaryContainer,
                ),
                columns: const [
                  DataColumn(label: Text('Company')),
                  DataColumn(label: Text('Contact Person')),
                  DataColumn(label: Text('Phone')),
                  DataColumn(label: Text('Email')),
                  DataColumn(label: Text('Purchase Orders')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Actions')),
                ],
                rows: suppliers
                    .map(
                      (supplier) => DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: 230,
                              child: Column(
                                // Two lines inside a 48px DataRow cell: without
                                // `min` the Column claims the full cell height
                                // and overflows by ~12px, which is a rendering
                                // error the table never showed while it was fed
                                // fixtures that no widget test rendered.
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    supplier.companyName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    supplier.address,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          DataCell(Text(supplier.contactPerson)),
                          DataCell(Text(supplier.phone)),
                          DataCell(Text(supplier.email)),
                          DataCell(Text('${purchaseCount(supplier.id)}')),
                          DataCell(
                            Chip(
                              label: Text(
                                supplier.isActive ? 'Active' : 'Inactive',
                              ),
                            ),
                          ),
                          DataCell(
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (onEdit case final edit?)
                                  IconButton(
                                    tooltip: 'Edit supplier',
                                    onPressed: () => edit(supplier),
                                    icon: const Icon(
                                      Icons.edit_outlined,
                                      size: 18,
                                    ),
                                  ),
                                IconButton(
                                  tooltip: supplier.isActive
                                      ? 'Deactivate supplier'
                                      : 'Activate supplier',
                                  onPressed: () => onToggle(supplier),
                                  icon: Icon(
                                    supplier.isActive
                                        ? Icons.block_outlined
                                        : Icons.check_circle_outline,
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
