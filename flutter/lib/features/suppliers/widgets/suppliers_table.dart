import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';

/// The supplier book as the shared [DataPanel]: a table on a wide panel, cards
/// under 720 px of panel width.
///
/// The seven column `DataTable` this replaces scrolled sideways at 760 px, so
/// the active toggle and the row actions sat off the right edge. The email moved
/// into the edit dialog, where it is read and written; the row keeps what the
/// list is for: who the supplier is, how to reach them, and how much is on order.
class SuppliersTable extends StatelessWidget {
  const SuppliersTable({
    super.key,
    required this.suppliers,
    required this.openOrderCount,
    required this.onEdit,
    required this.onToggle,
    required this.onNewOrder,
    required this.emptyMessage,
    this.isLoading = false,
    this.error,
    this.onRetry,
  });

  final List<Supplier> suppliers;

  /// Purchase orders still in flight for a supplier: draft, ordered or partly
  /// received. Completed and cancelled orders are not "open".
  final int Function(int supplierId) openOrderCount;

  /// Opens the edit dialog. Also the row tap.
  final ValueChanged<Supplier> onEdit;
  final ValueChanged<Supplier> onToggle;

  /// Opens a purchase order with this supplier already chosen.
  final ValueChanged<Supplier> onNewOrder;

  /// Worded by the page: "nothing loaded" and "nothing matches" differ.
  final String emptyMessage;

  final bool isLoading;
  final String? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return DataPanel<Supplier>(
      title: 'Suppliers',
      count: suppliers.length,
      rows: suppliers,
      isLoading: isLoading,
      error: error,
      onRetry: onRetry,
      emptyMessage: emptyMessage,
      onRowTap: onEdit,
      rowKey: (supplier) => ValueKey('SuppliersTable.row.${supplier.id}'),
      columns: [
        DataPanelColumn<Supplier>(
          label: 'Company',
          flex: 3,
          cell: (supplier) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                supplier.companyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                supplier.address.isEmpty
                    ? 'No address on file'
                    : supplier.address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        DataPanelColumn<Supplier>(
          label: 'Contact',
          flex: 2,
          cell: (supplier) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                supplier.contactPerson.isEmpty
                    ? 'No contact on file'
                    : supplier.contactPerson,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (supplier.phone.isNotEmpty)
                Text(
                  supplier.phone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
        DataPanelColumn<Supplier>(
          label: 'Open orders',
          numeric: true,
          flex: 2,
          cell: (supplier) =>
              Text(formatCount(openOrderCount(supplier.id)), maxLines: 1),
        ),
        DataPanelColumn<Supplier>(
          label: 'Status',
          flex: 2,
          cell: (supplier) => StatusBadge(
            label: supplier.isActive ? 'Active' : 'Inactive',
            tone: supplier.isActive ? StatusTone.success : StatusTone.neutral,
          ),
        ),
        DataPanelColumn<Supplier>(
          label: 'Actions',
          flex: 2,
          cell: (supplier) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'New order',
                onPressed: () => onNewOrder(supplier),
                icon: const Icon(Icons.add_shopping_cart_outlined, size: 18),
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
    );
  }
}
