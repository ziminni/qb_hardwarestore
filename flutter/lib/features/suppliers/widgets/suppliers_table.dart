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
  final ValueChanged<Supplier> onEdit;
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
                                IconButton(
                                  tooltip: 'Edit supplier',
                                  onPressed: () => onEdit(supplier),
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
