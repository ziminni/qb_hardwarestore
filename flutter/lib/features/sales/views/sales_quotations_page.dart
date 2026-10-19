import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/sales_module.dart';
import 'package:client/features/sales/viewmodels/sales_module_viewmodel.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
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

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<SalesModuleViewmodel>();
    final records = viewmodel.quotations;
    String label(SalesQuoteStatus value) =>
        value.name[0].toUpperCase() + value.name.substring(1);
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
                      label: label(item.status),
                      tone: tone(item.status),
                    ),
                    TextButton(onPressed: () {}, child: const Text('View')),
                  ],
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}
