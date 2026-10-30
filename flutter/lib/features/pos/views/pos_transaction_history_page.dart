import 'package:client/core/format/format.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/inventory_sales_status_badge.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:client/features/sales/widgets/sales_records_table.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// POS-native transaction history (tab 1).
///
/// Reuses the global [InventorySalesViewmodel] — same data as the sales
/// transactions page, wrapped in the POS shell so the cashier stays in the
/// POS workflow. See decisions 03 + 04.
class PosTransactionHistoryPage extends StatefulWidget {
  const PosTransactionHistoryPage({super.key});

  @override
  State<PosTransactionHistoryPage> createState() =>
      _PosTransactionHistoryPageState();
}

class _PosTransactionHistoryPageState extends State<PosTransactionHistoryPage> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InventorySalesViewmodel>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<InventorySalesViewmodel>();
    final sales = viewmodel.sales
        .where(
          (sale) =>
              '${sale.transactionNo} ${sale.customer} ${sale.paymentMethod}'
                  .toLowerCase()
                  .contains(_query.toLowerCase()),
        )
        .toList();

    return DashboardShell(
      title: 'Transaction History',
      subtitle: 'Review completed, refunded, and voided sales.',
      selectedNavigationIndex: 1,
      navigationItems: posNavigationItems,
      onNavigationSelected: (i) => navigatePos(context, i),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (viewmodel.loadError != null)
            LiveLoadErrorBanner(
              message: viewmodel.loadError!,
              onRetry: viewmodel.load,
            ),
          SizedBox(
            height: 48,
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Search transactions...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          const SizedBox(height: 16),
          if (viewmodel.isLoading && sales.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (sales.isEmpty && viewmodel.loadError == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('No transactions found.'),
              ),
            )
          else
            SalesRecordsTable(
              columns: const [
                'Transaction',
                'Date',
                'Customer',
                'Payment',
                'Total',
                'Status',
              ],
              emptyMessage: 'No transactions found.',
              rows: sales
                  .map(
                    (sale) => <Widget>[
                      Text(sale.transactionNo),
                      Text(formatDate(sale.date)),
                      Text(sale.customer),
                      Text(sale.paymentMethod),
                      Text(formatPeso(sale.total)),
                      InventorySalesStatusBadge.sale(status: sale.status),
                    ],
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }
}
