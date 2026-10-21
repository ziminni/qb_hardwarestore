import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/sales_module.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_records_table.dart';
import 'package:client/features/sales/widgets/sales_status_badge.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SalesOrdersPage extends StatefulWidget {
  const SalesOrdersPage({super.key});

  @override
  State<SalesOrdersPage> createState() => _SalesOrdersPageState();
}

class _SalesOrdersPageState extends State<SalesOrdersPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SalesModuleViewmodel>().load();
    });
  }

  /// Opens the read-only document sheet (decision D-02). Same seam as the
  /// quotations page: catalogue names when loaded, ids when not.
  void _showOrderSheet(BuildContext context, SalesOrderRecord item) {
    final inventory = context.read<InventoryViewmodel?>();
    showSalesDocumentSheet(
      context,
      title: item.number,
      fields: [
        ('Customer', item.customer),
        ('Status', _orderStatusLabel(item.status)),
        ('Order date', _shortDate(item.date)),
        if ((item.notes ?? '').isNotEmpty) ('Notes', item.notes!),
      ],
      lines: [
        for (final line in item.items)
          SalesDocumentLine(
            name: variantUomName(inventory, line.variantUomId),
            qty: line.qty,
            unitPrice: line.unitPrice,
          ),
      ],
      total: salesMoney(item.total),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<SalesModuleViewmodel>();
    final records = viewmodel.orders;
    String tone(SalesOrderStatus value) => switch (value) {
      SalesOrderStatus.completed => 'success',
      SalesOrderStatus.ready => 'info',
      SalesOrderStatus.processing => 'warning',
      _ => 'default',
    };
    return SalesSkeletonLayout(
      title: 'Sales Orders',
      subtitle: 'Track confirmed orders from preparation through completion.',
      selectedNavigationIndex: 3,
      onNavigationSelected: (index) => navigateSales(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (viewmodel.loadError != null)
            LiveLoadErrorBanner(
              message: viewmodel.loadError!,
              onRetry: viewmodel.load,
            ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: () {},
              icon: const Icon(Icons.add),
              label: const Text('New sales order'),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SalesRecordsTable(
            columns: const [
              'Order',
              'Customer',
              'Order Date',
              'Total',
              'Status',
              'Actions',
            ],
            emptyMessage: 'No sales orders available.',
            rows: records
                .map(
                  (item) => <Widget>[
                    Text(item.number),
                    Text(item.customer),
                    Text(
                      '${item.date.month}/${item.date.day}/${item.date.year}',
                    ),
                    Text('₱${item.total.toStringAsFixed(2)}'),
                    SalesStatusBadge(
                      label: _orderStatusLabel(item.status),
                      tone: tone(item.status),
                    ),
                    TextButton(
                      onPressed: () => _showOrderSheet(context, item),
                      child: const Text('View'),
                    ),
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

String _orderStatusLabel(SalesOrderStatus value) =>
    value.name[0].toUpperCase() + value.name.substring(1);

String _shortDate(DateTime date) =>
    '${date.month}/${date.day}/${date.year}';
