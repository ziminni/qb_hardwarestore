import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/inventory_sales_status_badge.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:client/features/sales/widgets/sales_document_sheet.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:client/features/sales/widgets/sales_records_table.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SalesTransactionsPage extends StatefulWidget {
  const SalesTransactionsPage({super.key});
  @override
  State<SalesTransactionsPage> createState() => _SalesTransactionsPageState();
}

class _SalesTransactionsPageState extends State<SalesTransactionsPage> {
  String query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InventorySalesViewmodel>().load();
    });
  }

  /// Opens the read-only document sheet (decision D-02).
  ///
  /// The transaction already carries its lines and payments, so nothing is
  /// fetched here. Payments show method and amount; a row with none falls back
  /// to the method name rather than inventing an amount.
  void _showTransactionSheet(BuildContext context, InventorySale sale) {
    showSalesDocumentSheet(
      context,
      title: sale.transactionNo,
      fields: [
        ('Date', '${sale.date.month}/${sale.date.day}/${sale.date.year}'),
        ('Customer', sale.customer),
        ('Cashier', sale.cashier),
        ('Source', sale.source),
        ('Status', sale.status.label),
        if (sale.payments.isEmpty)
          ('Payment', TenderMethod.labelFor(sale.paymentMethod))
        else
          for (final payment in sale.payments)
            (
              'Payment (${TenderMethod.labelFor(payment.method)})',
              salesMoney(payment.amount),
            ),
      ],
      lines: [
        for (final line in sale.lines)
          SalesDocumentLine(
            name: line.productName,
            qty: line.quantity,
            unitPrice: line.unitPrice,
          ),
      ],
      total: salesMoney(sale.total),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<InventorySalesViewmodel>();
    final sales = viewmodel.sales
        .where(
          (sale) =>
              '${sale.transactionNo} ${sale.customer} ${sale.paymentMethod}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
        )
        .toList();
    return SalesSkeletonLayout(
      title: 'Sales Transactions',
      subtitle: 'Review completed, refunded, and voided sales.',
      selectedNavigationIndex: 1,
      onNavigationSelected: (index) => navigateSales(context, index),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (viewmodel.loadError != null)
            LiveLoadErrorBanner(
              message: viewmodel.loadError!,
              onRetry: viewmodel.load,
            ),
          SizedBox(
            width: 360,
            child: TextField(
              onChanged: (value) => setState(() => query = value),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Transaction, customer, or payment',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SalesRecordsTable(
            columns: const [
              'Transaction',
              'Date',
              'Customer',
              'Source',
              'Payment',
              'Total',
              'Status',
              'Action',
            ],
            emptyMessage: 'No sales transactions match your search.',
            rows: sales
                .map(
                  (sale) => <Widget>[
                    Text(sale.transactionNo),
                    Text(
                      '${sale.date.month}/${sale.date.day}/${sale.date.year}',
                    ),
                    Text(sale.customer),
                    Text(sale.source),
                    Text(sale.paymentMethod),
                    Text('₱${sale.total.toStringAsFixed(2)}'),
                    InventorySalesStatusBadge.sale(status: sale.status),
                    TextButton(
                      onPressed: () => _showTransactionSheet(context, sale),
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
