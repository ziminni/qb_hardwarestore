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

class SalesQuotationsPage extends StatefulWidget {
  const SalesQuotationsPage({super.key});

  @override
  State<SalesQuotationsPage> createState() => _SalesQuotationsPageState();
}

class _SalesQuotationsPageState extends State<SalesQuotationsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<SalesModuleViewmodel>().load();
    });
  }

  /// Opens the read-only document sheet (decision D-02).
  ///
  /// Reads the app-scoped catalogue once per tap to turn `variant_uom` ids into
  /// names. A missing catalogue is not an error: [variantUomName] falls back to
  /// the id.
  void _showQuotationSheet(BuildContext context, SalesQuotation item) {
    final inventory = context.read<InventoryViewmodel?>();
    showSalesDocumentSheet(
      context,
      title: item.number,
      fields: [
        ('Customer', item.customer),
        ('Status', _quoteStatusLabel(item.status)),
        ('Created', _shortDate(item.date)),
        ('Valid until', _shortDate(item.validUntil)),
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
    final records = viewmodel.quotations;
    String tone(SalesQuoteStatus value) => switch (value) {
      SalesQuoteStatus.accepted => 'success',
      SalesQuoteStatus.sent => 'info',
      SalesQuoteStatus.expired => 'error',
      _ => 'default',
    };
    return SalesSkeletonLayout(
      title: 'Quotations',
      subtitle: 'Prepare and track customer estimates before an order.',
      selectedNavigationIndex: 2,
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
              label: const Text('New quotation'),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SalesRecordsTable(
            columns: const [
              'Quotation',
              'Customer',
              'Created',
              'Valid Until',
              'Total',
              'Status',
              'Actions',
            ],
            emptyMessage: 'No quotations available.',
            rows: records
                .map(
                  (item) => <Widget>[
                    Text(item.number),
                    Text(item.customer),
                    Text(
                      '${item.date.month}/${item.date.day}/${item.date.year}',
                    ),
                    Text(
                      '${item.validUntil.month}/${item.validUntil.day}/${item.validUntil.year}',
                    ),
                    Text('₱${item.total.toStringAsFixed(2)}'),
                    SalesStatusBadge(
                      label: _quoteStatusLabel(item.status),
                      tone: tone(item.status),
                    ),
                    TextButton(
                      onPressed: () => _showQuotationSheet(context, item),
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

String _quoteStatusLabel(SalesQuoteStatus value) =>
    value.name[0].toUpperCase() + value.name.substring(1);

String _shortDate(DateTime date) => '${date.month}/${date.day}/${date.year}';
