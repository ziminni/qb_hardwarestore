import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/widgets/inventory_sales_status_badge.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:client/features/sales/widgets/sales_records_table.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The stocker's Returns tab (decision D-01): a READ-ONLY list of transactions
/// whose `source` is `RETURN`.
///
/// Why read-only: the `inventory` role is granted GET on `/api/v1/transactions/`
/// by `IsPOSOrReadOnly`, so listing returns costs no backend work, while
/// initiating one needs a `process_return` flow that does not exist yet (map
/// fog). The viewmodel is the app-scoped `InventorySalesViewmodel` — the same
/// one the sales screens use — so a return rated once cannot disagree with
/// itself on two screens.
///
/// A stocker reaching this page with no rows sees "No returns recorded." rather
/// than an empty table, and a failed load keeps its error and a retry.
class InventoryReturnsPage extends StatefulWidget {
  const InventoryReturnsPage({super.key});

  @override
  State<InventoryReturnsPage> createState() => _InventoryReturnsPageState();
}

class _InventoryReturnsPageState extends State<InventoryReturnsPage> {
  @override
  void initState() {
    super.initState();
    // The provider is app-scoped (see main.dart), so it outlives this page and
    // is read after the first frame rather than during initState.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<InventorySalesViewmodel>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<InventorySalesViewmodel>();
    final returns = viewmodel.returns;
    return InventorySkeletonLayout(
      title: 'Returns & Refunds',
      subtitle: 'Track returned transactions.',
      selectedNavigationIndex: 10,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: viewmodel.isLoading && returns.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (viewmodel.loadError != null)
                  LiveLoadErrorBanner(
                    message: viewmodel.loadError!,
                    onRetry: viewmodel.load,
                  ),
                const SizedBox(height: AppSpacing.md),
                SalesRecordsTable(
                  columns: const [
                    'Return ref',
                    'Date',
                    'Product',
                    'Qty',
                    'Status',
                  ],
                  emptyMessage: 'No returns recorded.',
                  rows: [
                    for (final item in returns)
                      <Widget>[
                        Text(item.reference),
                        Text(
                          '${item.date.month}/${item.date.day}/${item.date.year}',
                        ),
                        Text('${item.productName} — ${item.variantName}'),
                        Text(item.quantity.toStringAsFixed(0)),
                        InventorySalesStatusBadge.returnStatus(
                          status: item.status,
                        ),
                      ],
                  ],
                ),
              ],
            ),
    );
  }
}
