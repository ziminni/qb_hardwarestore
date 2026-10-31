import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/features/dashboard/viewmodels/admin_overview_viewmodel.dart';
import 'package:client/features/dashboard/widget/admin_needs_attention_panel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/data_panel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:client/shared/widgets/status_badge.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// The administrator's overview: today's numbers and what waits on the admin.
///
/// Every number comes from a live read: today's sales summary and the latest
/// transactions (reports and sales services, owned by
/// [AdminOverviewViewmodel]), the requisition queue, and stock counts from the
/// shared [InventoryViewmodel], the same derivation the stock screens use, so
/// this page can never contradict them about the same row.
///
/// Pages the admin cannot open are not offered: D11 removed "Add product",
/// because the router sends this role back to its own dashboard and the button
/// looked live while doing nothing. What remains is work with a destination.
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  /// How many rows each list shows before the screen it summarises takes over.
  static const int _rowLimit = 5;

  /// The content width from which the sales preview and "Needs attention" sit
  /// side by side. Below it they stack: at 760 px a half-width column leaves
  /// about 330 px, where every label wraps and the actions crowd the counts.
  static const double _twoColumnWidth = 900;

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

  AdminSkeletonLayout _shell(Widget child) => AdminSkeletonLayout(
    title: 'Admin Dashboard',
    subtitle: 'Monitor today’s business performance and operations.',
    selectedNavigationIndex: 0,
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final overview = context.watch<AdminOverviewViewmodel>();
    final inventory = context.watch<InventoryViewmodel>();

    // A failed FIRST load is ONE failure: the banner and its retry. A tile
    // reading ₱0.00, or a list saying no sale was recorded, would state facts
    // over a read that never answered.
    if (!overview.hasLoaded && overview.loadError != null) {
      return _shell(
        ErrorBanner(message: overview.loadError!, onRetry: overview.load),
      );
    }
    if (!overview.hasLoaded) {
      return _shell(const Center(child: CircularProgressIndicator()));
    }

    final today = overview.today!;
    // Stock counts are only true once the inventory load has succeeded: before
    // that the viewmodel holds bundled rows (or nothing), and rendering their
    // count as data would present invented zeros. hasLoaded is set even on
    // failure (the shared keep-rows contract), so a failed load must also
    // unready the numbers.
    final stockReady = inventory.hasLoaded && inventory.loadError == null;

    var lowStock = 0;
    var outOfStock = 0;
    for (final product in inventory.products) {
      for (final variant in product.variants) {
        final status = inventory.statusForVariant(variant.id);
        if (status == InventoryStockStatus.lowStock) lowStock++;
        if (status == InventoryStockStatus.outOfStock) outOfStock++;
      }
    }
    // The same valuation the stock screens use: every live batch at its landed
    // cost, not a price the catalogue wishes it had.
    final inventoryValue = inventory.batches.fold<double>(
      0,
      (sum, batch) => sum + batch.currentQty * batch.unitCostLanded,
    );
    final unresolvedAlerts = inventory.alerts
        .where((alert) => !alert.isResolved)
        .length;

    final stockFailure = inventory.loadError;

    return _shell(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (overview.loadError != null) ...[
            // A refresh failed over numbers already read: keep them, name the
            // failure once, and leave the retry that re-reads all three.
            ErrorBanner(message: overview.loadError!, onRetry: overview.load),
            const SizedBox(height: AppSpacing.lg),
          ],
          if (stockFailure != null) ...[
            // The stock half failed: name it and leave the retry that re-reads
            // exactly this half. The sales numbers below are still true.
            ErrorBanner(
              message: 'Stock data could not be loaded. $stockFailure',
              onRetry: inventory.load,
            ),
            const SizedBox(height: AppSpacing.lg),
          ] else if (!inventory.hasLoaded) ...[
            const Text('Loading stock data…'),
            const SizedBox(height: AppSpacing.md),
          ],
          MetricGrid(
            // 300 px: three tiles across at 1440 and at 1100, two at 760. Six
            // tiles fill every row at each of those widths; the 240 px the
            // first pass used gave four plus two at 1440, leaving half a row
            // empty.
            minTileWidth: 300,
            children: [
              MetricTile(
                label: 'Today sales',
                value: formatPeso(today.totalGross),
                caption: 'Gross today',
              ),
              MetricTile(
                label: 'Transactions',
                value: formatCount(today.totalTransactions),
                caption: 'Recorded today',
              ),
              if (stockReady) ...[
                MetricTile(
                  label: 'Products',
                  value: formatCount(inventory.products.length),
                  caption: 'In the catalogue',
                ),
                MetricTile(
                  label: 'Low stock',
                  value: formatCount(lowStock),
                  caption: 'Under its reorder level',
                ),
                MetricTile(
                  label: 'Out of stock',
                  value: formatCount(outOfStock),
                  caption: 'Nothing on hand',
                ),
                MetricTile(
                  label: 'Inventory value',
                  value: formatPeso(inventoryValue),
                  caption: 'On hand at landed cost',
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final sales = AppPanel(
                title: 'Today sales',
                trailing: TextButton(
                  onPressed: () => _go(AppRoutes.adminSales),
                  child: const Text('Open sales'),
                ),
                child: _SalesSummary(summary: today),
              );
              final attention = AdminNeedsAttentionPanel(
                items: [
                  AdminAttentionItem(
                    label: 'Requisitions waiting for approval',
                    value: formatCount(overview.awaitingApproval),
                    actionLabel: 'Review requisitions',
                    onAction: () => _go(AppRoutes.adminRequisitions),
                  ),
                  // Only when the alert feed answered: an unloaded count would
                  // read as "nothing is wrong".
                  if (stockReady)
                    AdminAttentionItem(
                      label: 'Unresolved alerts',
                      value: formatCount(unresolvedAlerts),
                      actionLabel: 'Open monitoring',
                      onAction: () => _go(AppRoutes.adminInventory),
                    ),
                ],
              );

              if (constraints.maxWidth < _twoColumnWidth) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    sales,
                    const SizedBox(height: AppSpacing.lg),
                    attention,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: sales),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(flex: 2, child: attention),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          _SectionHeading(
            title: 'Recent sales',
            actionLabel: 'View all',
            onAction: () => _go(AppRoutes.adminSales),
          ),
          const SizedBox(height: AppSpacing.md),
          DataPanel<TransactionRecord>(
            columns: [
              DataPanelColumn(
                label: 'Transaction',
                flex: 3,
                cell: (row) => Text(
                  row.transactionNo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DataPanelColumn(
                label: 'Customer',
                flex: 3,
                cell: (row) => Text(
                  row.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              DataPanelColumn(
                label: 'Date',
                flex: 2,
                cell: (row) => Text(formatDate(row.transDate)),
              ),
              DataPanelColumn(
                label: 'Total',
                numeric: true,
                flex: 2,
                cell: (row) => Text(formatPeso(row.grandTotal)),
              ),
            ],
            rows: overview.recentTransactions,
            emptyMessage: 'No sales recorded yet.',
            onRowTap: (_) => _go(AppRoutes.adminSales),
            rowKey: (row) => ValueKey('admin-recent-sale-${row.id}'),
          ),
          // The alert feed is only true once the stock read answered: an empty
          // table under a failed load would say "nothing is wrong".
          if (stockReady) ...[
            const SizedBox(height: AppSpacing.xl),
            const _SectionHeading(title: 'Alerts'),
            const SizedBox(height: AppSpacing.md),
            DataPanel<SystemAlert>(
              columns: [
                DataPanelColumn(
                  label: 'Alert',
                  flex: 2,
                  cell: (row) => Text(row.type.displayName),
                ),
                DataPanelColumn(
                  label: 'Message',
                  flex: 4,
                  cell: (row) => Text(
                    row.message,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataPanelColumn(
                  label: 'Status',
                  flex: 2,
                  cell: (row) => StatusBadge(
                    label: row.isResolved ? 'Resolved' : 'Open',
                    tone: row.isResolved
                        ? StatusTone.neutral
                        : StatusTone.warning,
                  ),
                ),
              ],
              // Newest first, and the ones that still need a decision above
              // the ones already cleared.
              rows:
                  ([...inventory.alerts]..sort((a, b) {
                        if (a.isResolved != b.isResolved) {
                          return a.isResolved ? 1 : -1;
                        }
                        return b.id.compareTo(a.id);
                      }))
                      .take(_rowLimit)
                      .toList(),
              emptyMessage: 'No active alerts.',
              onRowTap: (_) => _go(AppRoutes.adminInventory),
              rowKey: (row) => ValueKey('admin-alert-${row.id}'),
            ),
          ],
        ],
      ),
    );
  }
}

/// The three numbers behind today's gross, read from the server's summary.
///
/// No Discounts row (D12): checkout hard-zeroes the discount, so the row could
/// only ever read ₱0.00 and advertise a feature the system does not have.
class _SalesSummary extends StatelessWidget {
  const _SalesSummary({required this.summary});

  final SalesSummary summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatRow(
          label: 'Transactions',
          value: formatCount(summary.totalTransactions),
        ),
        _StatRow(label: 'Gross sales', value: formatPeso(summary.totalGross)),
        _StatRow(label: 'VAT', value: formatPeso(summary.totalVat)),
      ],
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// A list's heading above its card: `DataPanel` brings the card but no title,
/// and an `AppPanel` around it would draw a second border.
class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final label = actionLabel;
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTextStyles.cinzelFont,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (label != null) TextButton(onPressed: onAction, child: Text(label)),
      ],
    );
  }
}
