import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/features/dashboard/viewmodels/admin_overview_viewmodel.dart';
import 'package:client/features/dashboard/widget/admin_action_button.dart';
import 'package:client/features/dashboard/widget/admin_list_item.dart';
import 'package:client/features/dashboard/widget/admin_metric_card.dart';
import 'package:client/features/dashboard/widget/admin_section.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// The administrator's dashboard page.
///
/// Every section reads live endpoints: today's sales from the reports
/// sales-summary, stock counts from the shared inventory viewmodel (the same
/// derivation the stock screens use), recent activity from the latest sales
/// transactions, and system alerts from the server alert feed. Sections with
/// no wired source do not render — the old screen's "Active users" card and
/// static "Sales chart" text had no backend behind them.
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<AdminOverviewViewmodel>().load();
      context.read<InventoryViewmodel>().load();
    });
  }

  void _go(String location) => context.go(location);

  @override
  Widget build(BuildContext context) {
    final overview = context.watch<AdminOverviewViewmodel>();
    final inventory = context.watch<InventoryViewmodel>();

    if (overview.isLoading && !overview.hasLoaded) {
      return AdminSkeletonLayout(
        title: 'Admin Dashboard',
        subtitle: 'Monitor today’s business performance and operations.',
        selectedNavigationIndex: 0,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (!overview.hasLoaded && overview.loadError != null) {
      return AdminSkeletonLayout(
        title: 'Admin Dashboard',
        subtitle: 'Monitor today’s business performance and operations.',
        selectedNavigationIndex: 0,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LiveLoadErrorBanner(
              message: overview.loadError!,
              onRetry: overview.load,
            ),
            const SizedBox(height: 16),
            const Text('No overview data available.'),
          ],
        ),
      );
    }
    if (!overview.hasLoaded) {
      return AdminSkeletonLayout(
        title: 'Admin Dashboard',
        subtitle: 'Monitor today’s business performance and operations.',
        selectedNavigationIndex: 0,
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final today = overview.today!;
    var lowStock = 0;
    var outOfStock = 0;
    for (final product in inventory.products) {
      for (final variant in product.variants) {
        final status = inventory.statusForVariant(variant.id);
        if (status.name == 'lowStock') lowStock++;
        if (status.name == 'outOfStock') outOfStock++;
      }
    }
    // Stock counts are only true once the inventory load has succeeded: before
    // that the viewmodel holds bundled rows (or nothing), and rendering their
    // count as data would present invented zeros — the same defect the 6D pass
    // found on the till. hasLoaded is set even on failure (the shared
    // keep-rows contract), so a failed load must also unready the metrics —
    // except after a successful load, where stale rows under the banner stand.
    final stockReady = inventory.hasLoaded && inventory.loadError == null;
    final metrics = [
      ('Today sales', '₱${today.totalGross.toStringAsFixed(2)}'),
      if (stockReady) ('Products', '${inventory.products.length}'),
      if (stockReady) ('Low stock', '$lowStock'),
      if (stockReady) ('Out of stock', '$outOfStock'),
    ];

    return AdminSkeletonLayout(
      title: 'Admin Dashboard',
      subtitle: 'Monitor today’s business performance and operations.',
      selectedNavigationIndex: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (overview.loadError != null || inventory.loadError != null)
            LiveLoadErrorBanner(
              message:
                  overview.loadError ??
                  inventory.loadError ??
                  'Could not load.',
              onRetry: () {
                overview.load();
                inventory.load();
              },
            ),
          if (overview.loadError != null || inventory.loadError != null)
            const SizedBox(height: 16),
          if (!stockReady)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                inventory.isLoading
                    ? 'Loading stock data…'
                    : 'Stock data could not be loaded.',
              ),
            ),
          if (stockReady)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final metric in metrics)
                  SizedBox(
                    width: 190,
                    child: AdminMetricCard(label: metric.$1, value: metric.$2),
                  ),
              ],
            ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: AdminSection(
                  title: 'Sales summary',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Today: ${today.totalTransactions} transactions · '
                        '₱${today.totalGross.toStringAsFixed(2)} gross',
                      ),
                      Text(
                        'VAT ₱${today.totalVat.toStringAsFixed(2)} · '
                        'Discounts ₱${today.totalDiscounts.toStringAsFixed(2)}',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AdminSection(
                  title: 'Quick actions',
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      AdminActionButton(
                        label: 'Create user',
                        onPressed: () => _go(AppRoutes.adminUserManagement),
                      ),
                      AdminActionButton(
                        label: 'Add product',
                        onPressed: () => _go(AppRoutes.inventoryProducts),
                      ),
                      AdminActionButton(
                        label: 'View reports',
                        onPressed: () => _go(AppRoutes.adminReports),
                      ),
                      AdminActionButton(
                        label: 'Settings',
                        onPressed: () => _go(AppRoutes.adminSettings),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AdminSection(
                  title: 'Recent activity',
                  actionLabel: 'View all',
                  onAction: () => _go(AppRoutes.adminSales),
                  child: Column(
                    children: overview.recentTransactions.isEmpty
                        ? [const Text('No recent sales.')]
                        : [
                            for (final row in overview.recentTransactions)
                              AdminListItem(
                                title:
                                    '${row.transactionNo} · ${row.customerName}',
                                subtitle:
                                    '${row.transDate.month}/${row.transDate.day}/${row.transDate.year} · ${row.source}',
                                trailing:
                                    '₱${row.grandTotal.toStringAsFixed(2)}',
                              ),
                          ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: AdminSection(
                  title: 'System alerts',
                  child: Column(
                    children: inventory.alerts.isEmpty
                        ? [const Text('No active alerts.')]
                        : [
                            for (final alert in inventory.alerts)
                              AdminListItem(
                                title: alert.type.displayName,
                                subtitle: alert.message,
                                trailing: alert.isResolved ? 'Resolved' : null,
                              ),
                          ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
