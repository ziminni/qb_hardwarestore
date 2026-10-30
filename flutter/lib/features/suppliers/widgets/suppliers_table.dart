import 'package:client/data/models/supplier.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/status_pill.dart';
import 'package:client/core/constants/app_colors.dart';
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
    return DataPanel(
      title: 'Supplier directory',
      subtitle: 'Vendors available for purchase orders',
      count: suppliers.length,
      isEmpty: suppliers.isEmpty,
      emptyIcon: Icons.local_shipping_outlined,
      emptyTitle: 'No suppliers found',
      emptyMessage: 'No suppliers match this search.',
      child: DataTable(
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
                            style: const TextStyle(fontWeight: FontWeight.w600),
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
                    StatusPill(
                      label: supplier.isActive ? 'Active' : 'Inactive',
                      color: supplier.isActive
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Edit supplier',
                          onPressed: () => onEdit(supplier),
                          icon: const Icon(Icons.edit_outlined, size: 18),
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
    );
  }
}
