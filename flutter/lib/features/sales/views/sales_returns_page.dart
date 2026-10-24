import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/inventory_sales_status_badge.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_records_table.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SalesReturnsPage extends StatefulWidget {
  const SalesReturnsPage({super.key});

  @override
  State<SalesReturnsPage> createState() => _SalesReturnsPageState();
}

class _SalesReturnsPageState extends State<SalesReturnsPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InventorySalesViewmodel>().load();
    });
  }

  /// Opens the read-only return details sheet — the same document sheet the
  /// transactions page uses (decision D-02 pattern).
  ///
  /// `View` here was `TextButton(onPressed: () {}, ...)`: it swallowed the tap.
  /// A posted return is immutable, so this sheet only reads: reference, the
  /// original sale it reverses, every line with its quantity, the reason, the
  /// refund and who processed it.
  void _showReturnSheet(BuildContext context, InventoryReturn item) {
    showSalesDocumentSheet(
      context,
      title: item.reference,
      fields: [
        ('Original sale', item.relatedReference),
        ('Date', '${item.date.month}/${item.date.day}/${item.date.year}'),
        ('Cashier', item.processedBy),
        ('Reason', item.reason),
        ('Status', item.status.label),
      ],
      lines: [
        for (final line in item.lines)
          SalesDocumentLine(
            // The wire carries no product names, only the selling-unit code
            // (same limitation the transactions sheet states), so the code is
            // the line name rather than an invented one.
            name: line.productName,
            qty: line.quantity,
            unitPrice: line.unitPrice,
          ),
      ],
      total: salesMoney(item.total),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<InventorySalesViewmodel>();
    final records = viewmodel.returns;
    return SalesSkeletonLayout(
      title: 'Returns & Refunds',
      subtitle: 'Review customer returns, replacements, and refund outcomes.',
      selectedNavigationIndex: 5,
      onNavigationSelected: (index) => navigateSales(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (viewmodel.loadError != null)
            LiveLoadErrorBanner(
              message: viewmodel.loadError!,
              onRetry: viewmodel.load,
            ),
          // "New customer return" is GONE (Phase 3 Task 0): a cashier returns
          // from the till's Returns tab (Task 4), and the manager's
          // unlinked-return screen is Phase 5. Nothing here could create one.
          const SizedBox(height: AppSpacing.xl),
          SalesRecordsTable(
            columns: const [
              'Return',
              'Date',
              'Transaction',
              'Product',
              'Quantity',
              'Reason',
              'Status',
              'Action',
            ],
            emptyMessage: 'No customer returns available.',
            rows: records
                .where((item) => item.type.name == 'customer')
                .map(
                  (item) => <Widget>[
                    Text(item.reference),
                    Text(
                      '${item.date.month}/${item.date.day}/${item.date.year}',
                    ),
                    Text(item.relatedReference),
                    Text('${item.productName} — ${item.variantName}'),
                    Text(item.quantity.toStringAsFixed(0)),
                    Text(item.reason),
                    InventorySalesStatusBadge.returnStatus(status: item.status),
                    TextButton(
                      onPressed: () => _showReturnSheet(context, item),
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
