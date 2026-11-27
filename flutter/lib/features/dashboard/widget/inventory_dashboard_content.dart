import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/dashboard/widget/inventory_action_button.dart';
import 'package:client/features/dashboard/widget/inventory_fifo_pipeline_card.dart';
import 'package:client/features/dashboard/widget/inventory_recent_adjustments_panel.dart';
import 'package:client/features/dashboard/widget/inventory_restock_queue_panel.dart';
import 'package:client/features/dashboard/widget/inventory_waiting_to_receive_panel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/analytics_charts.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/operational_charts.dart';
import 'package:client/shared/widgets/stitch_ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Inventory home screen content, wired to live data: "what needs me today".
///
/// Decision: every stock number on this page reads `InventoryViewmodel` — the
/// same derivation the stock screens use, not the alerts endpoint — so the
/// dashboard can never contradict them about the same row. The one exception is
/// "Waiting to receive", which reads the purchase orders the Purchasing screens
/// already load: they are a different authority (an order, not stock), and no
/// panel here invents a number the wire does not carry.
class InventoryDashboardContent extends StatefulWidget {
  const InventoryDashboardContent({super.key});

  @override
  State<InventoryDashboardContent> createState() =>
      _InventoryDashboardContentState();
}

/// How many rows [buildInventoryRestockPanel], [buildInventoryWaitingPanel] and
/// the recent-adjustments panel show before they count the rest.
const int _dashboardRowLimit = 5;

/// The restock queue: most urgent first (zero stock before low stock, then the
/// lowest coverage, on hand / reorder level). Shared by the Stock dashboard and
/// the combined landing (Phase 2 F4), so both read the SAME derivation the Low
/// stock screen uses — never a number this file invents on its own.
///
/// A silent `take(5)` once hid a zero-stock variant at position 6 while the
/// manager restocked others, so the panel also says how many were cut.
List<InventoryRestockRow> _restockRows(InventoryViewmodel inventory) =>
    [
      for (final product in inventory.products)
        for (final variant in product.variants)
          if (inventory.statusForVariant(variant.id) !=
              InventoryStockStatus.inStock)
            InventoryRestockRow(
              variantId: variant.id,
              item: '${product.baseName} ${variant.variantName}',
              onHand: inventory.stockOnHandFor(variant.id),
              threshold: variant.minStockThreshold,
              status: inventory.statusForVariant(variant.id),
            ),
    ]..sort((a, b) {
      final aOut = a.onHand <= 0;
      final bOut = b.onHand <= 0;
      if (aOut != bOut) return aOut ? -1 : 1;
      double coverage(InventoryRestockRow row) =>
          row.threshold > 0 ? row.onHand / row.threshold : 0;
      return coverage(a).compareTo(coverage(b));
    });

Widget buildInventoryRestockPanel(
  BuildContext context,
  InventoryViewmodel inventory,
) {
  final needsRestock = _restockRows(inventory);

  return InventoryRestockQueuePanel(
    rows: needsRestock.take(_dashboardRowLimit).toList(),
    total: needsRestock.length,
    emptyMessage: 'Nothing to restock.',
    // The dashboard cannot clear a shortage, only point at the screen that
    // can: every row and the header lead to Low stock, where Reorder lives.
    onViewAll: () => context.go(AppRoutes.inventoryLowStock),
    onRowTap: (_) => context.go(AppRoutes.inventoryLowStock),
  );
}

/// The orders still owed to the store, soonest expected first. Shared by the
/// Stock dashboard and the combined landing (Phase 2 F4).
Widget buildInventoryWaitingPanel(
  BuildContext context,
  SuppliersPurchasesViewmodel purchases,
) {
  // Only the two states the server will accept a receipt against: a draft has
  // not been sent and a complete order has nothing left to come.
  final waiting =
      purchases.purchases
          .where(
            (order) =>
                order.status == PurchaseStatus.ordered ||
                order.status == PurchaseStatus.partial,
          )
          .toList()
        ..sort((a, b) {
          final aDate = a.expectedDelivery;
          final bDate = b.expectedDelivery;
          if (aDate == null && bDate == null) return a.id.compareTo(b.id);
          if (aDate == null) return 1;
          if (bDate == null) return -1;
          final byDate = aDate.compareTo(bDate);
          return byDate != 0 ? byDate : a.id.compareTo(b.id);
        });

  return InventoryWaitingToReceivePanel(
    orders: waiting.take(_dashboardRowLimit).toList(),
    total: waiting.length,
    emptyMessage: 'No purchase order is waiting to be received.',
    onViewAll: () => context.go(AppRoutes.inventoryReceiving),
    onRowTap: (_) => context.go(AppRoutes.inventoryReceiving),
    // A first read in flight shows the panel's spinner; a failure shows the
    // banner with the retry that re-reads just this list.
    isLoading: purchases.isLoading && waiting.isEmpty,
    error: purchases.isLoading ? null : purchases.loadError,
    onRetry: purchases.load,
  );
}

class _InventoryDashboardContentState extends State<InventoryDashboardContent> {
  /// The narrowest content width that still leaves a ~900 px restock table and
  /// a ~600 px "Waiting to receive" panel side by side.
  static const double _twoColumnWidth = 1520;

  @override
  void initState() {
    super.initState();
    // "Waiting to receive" needs the purchase orders, which only the Purchasing
    // screens fetch. Ask for them here, once, and only when nothing has arrived
    // yet: an empty list from a previous page is indistinguishable from "nothing
    // is on order", and this panel must not report the second when it means the
    // first. The store is app scoped, so the usual case is no request at all.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final purchases = context.read<SuppliersPurchasesViewmodel>();
      if (purchases.purchases.isEmpty && !purchases.isLoading) {
        purchases.load();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    final purchases = context.watch<SuppliersPurchasesViewmodel>();

    final failure = inventory.loadError;
    final pending = inventory.isLoading || !inventory.hasLoaded;

    if (pending && inventory.products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    // A failed FIRST load is ONE failure: the banner and its retry. A "no
    // products available" line under it would claim a fact the failed read never
    // established.
    if (failure != null && inventory.products.isEmpty) {
      return ErrorBanner(message: failure, onRetry: inventory.load);
    }

    var inStock = 0;
    var lowStock = 0;
    var outOfStock = 0;
    final variantCategory = <int, String>{};
    final variantLocation = <int, String>{};
    for (final product in inventory.products) {
      final cat = product.categoryName.isEmpty
          ? 'Uncategorized'
          : product.categoryName;
      final productLoc = product.storedAtName.isEmpty
          ? 'Main Store'
          : product.storedAtName;
      for (final variant in product.variants) {
        variantCategory[variant.id] = cat;
        variantLocation[variant.id] = variant.storedAtName.isNotEmpty
            ? variant.storedAtName
            : productLoc;
        final status = inventory.statusForVariant(variant.id);
        if (status == InventoryStockStatus.inStock) inStock++;
        if (status == InventoryStockStatus.lowStock) lowStock++;
        if (status == InventoryStockStatus.outOfStock) outOfStock++;
      }
    }

    final totalVariants = inStock + lowStock + outOfStock;
    final healthyRatio = totalVariants > 0 ? inStock / totalVariants : 0.0;
    final healthyPct = (healthyRatio * 100).round();

    var activeBatchesCount = 0;
    final valueByCategory = <String, double>{};
    final valueByLocation = <String, double>{};
    for (final batch in inventory.batches) {
      if (batch.currentQty <= 0) continue;
      activeBatchesCount++;
      final value = batch.currentQty * batch.unitCostLanded;
      final cat = variantCategory[batch.variantId] ?? 'Other';
      valueByCategory[cat] = (valueByCategory[cat] ?? 0) + value;
      final locName = variantLocation[batch.variantId] ?? 'Main Store';
      valueByLocation[locName] = (valueByLocation[locName] ?? 0) + value;
    }
    final topCategories = valueByCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topLocations = valueByLocation.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // The same valuation the stock screens use: every live batch at its landed
    // cost, not a price the catalogue wishes it had.
    final inventoryValue = inventory.batches.fold<double>(
      0,
      (sum, batch) => sum + batch.currentQty * batch.unitCostLanded,
    );

    final waitingPoCount = purchases.purchases
        .where(
          (order) =>
              order.status == PurchaseStatus.ordered ||
              order.status == PurchaseStatus.partial,
        )
        .length;

    final criticalCount = lowStock + outOfStock;
    final restockRows = _restockRows(inventory);

    // Adjustment rows name the item, which the adjustment itself does not carry.
    final itemNames = <int, String>{
      for (final record in inventory.stockRecords)
        record.variant.id:
            '${record.product.baseName} ${record.variant.variantName}',
    };

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Stitch Top Action Bar
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          crossAxisAlignment: WrapCrossAlignment.center,
          alignment: WrapAlignment.spaceBetween,
          children: [
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: const [
                Text(
                  'Inventory overview',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: StitchColors.ink,
                  ),
                ),
                StitchPill(
                  label: 'Live Stock · Store & Bodega',
                  tone: StitchTone.success,
                  icon: Icons.circle,
                ),
              ],
            ),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('inventory-dashboard-refresh'),
                  onPressed: inventory.isLoading
                      ? null
                      : () {
                          inventory.load();
                          purchases.load();
                        },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Refresh'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('inventory-dashboard-reports'),
                  onPressed: () =>
                      context.go(AppRoutes.inventoryReportCatalogue),
                  icon: const Icon(Icons.analytics_outlined, size: 16),
                  label: const Text('Inventory reports'),
                ),
                InventoryActionButton(
                  label: 'Add product',
                  onPressed: () => context.go(AppRoutes.inventoryProducts),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        // A failed REFRESH keeps the rows it already had and says why above
        // them.
        if (failure != null) ...[
          ErrorBanner(message: failure, onRetry: inventory.load),
          const SizedBox(height: AppSpacing.lg),
        ],
        if (inventory.products.isEmpty)
          AppPanel(
            child: EmptyState(
              icon: Icons.inventory_2_outlined,
              message: 'No products available.',
              actionLabel: 'Open products',
              onAction: () => context.go(AppRoutes.inventoryProducts),
            ),
          )
        else ...[
          // 2. 4-Column Stitch Hero KPI Strip
          MetricGrid(
            minTileWidth: 230,
            children: [
              StitchKpiCard(
                key: const ValueKey('inventory-kpi-valuation'),
                label: 'FIFO Landed Valuation',
                value: formatPeso(inventoryValue),
                icon: Icons.account_balance_wallet_outlined,
                tone: StitchTone.primary,
                subtitle: 'On hand at landed cost',
                pillLabel:
                    '${formatCount(activeBatchesCount)} active ${activeBatchesCount == 1 ? 'batch' : 'batches'}',
                pillTone: StitchTone.primary,
              ),
              StitchKpiCard(
                key: const ValueKey('inventory-kpi-health'),
                label: 'Stock Health Coverage',
                value: '$healthyPct%',
                icon: Icons.verified_outlined,
                tone: healthyRatio >= 0.8
                    ? StitchTone.success
                    : (healthyRatio >= 0.5
                          ? StitchTone.warning
                          : StitchTone.danger),
                subtitle:
                    '${formatCount(inStock)} of ${formatCount(totalVariants)} variants healthy',
                progress: healthyRatio,
              ),
              StitchKpiCard(
                key: const ValueKey('inventory-kpi-depletion'),
                label: 'Critical Depletion Radar',
                value: '${formatCount(criticalCount)} SKUs',
                icon: Icons.warning_amber_rounded,
                tone: criticalCount > 0
                    ? StitchTone.danger
                    : StitchTone.success,
                valueColor: criticalCount > 0
                    ? StitchColors.danger
                    : StitchColors.ink,
                pillLabel: '${formatCount(outOfStock)} Out of stock',
                pillTone: outOfStock > 0
                    ? StitchTone.danger
                    : StitchTone.neutral,
                secondaryPillLabel: '${formatCount(lowStock)} Low stock',
                secondaryPillTone: lowStock > 0
                    ? StitchTone.warning
                    : StitchTone.neutral,
                onTap: () => context.go(AppRoutes.inventoryLowStock),
              ),
              StitchKpiCard(
                key: const ValueKey('inventory-kpi-products'),
                label: 'Total Products',
                value: formatCount(inventory.products.length),
                icon: Icons.inventory_2_outlined,
                tone: StitchTone.primary,
                subtitle: 'In the catalogue',
                pillLabel:
                    '${formatCount(waitingPoCount)} waiting ${waitingPoCount == 1 ? 'PO' : 'POs'}',
                pillTone: waitingPoCount > 0
                    ? StitchTone.warning
                    : StitchTone.neutral,
                onTap: () => context.go(AppRoutes.inventoryProducts),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          // 3. 2-Column Chart Hero (Left flex:3 Category + Location, Right flex:2 Donut)
          LayoutBuilder(
            builder: (context, constraints) {
              final healthChart = DonutChart(
                key: const ValueKey('inventory-dashboard-health-chart'),
                title: 'Stock Composition / Health',
                subtitle: 'Variants grouped by current stock status.',
                centerLabel: 'Variants',
                centerValue: formatCount(totalVariants),
                slices: [
                  if (inStock > 0)
                    ShareSlice(
                      label: 'Healthy / In stock',
                      value: inStock.toDouble(),
                      amountText: '${formatCount(inStock)} variants',
                    ),
                  if (lowStock > 0)
                    ShareSlice(
                      label: 'Low stock',
                      value: lowStock.toDouble(),
                      amountText: '${formatCount(lowStock)} variants',
                    ),
                  if (outOfStock > 0)
                    ShareSlice(
                      label: 'Out of stock',
                      value: outOfStock.toDouble(),
                      amountText: '${formatCount(outOfStock)} variants',
                    ),
                ],
              );

              final categoryChart = topCategories.isEmpty
                  ? null
                  : HorizontalComparisonChart(
                      key: const ValueKey('inventory-dashboard-category-chart'),
                      title: 'Inventory Value by Category',
                      subtitle: 'On-hand stock valued at landed FIFO cost.',
                      primaryLabel: 'Value at cost',
                      items: [
                        for (final entry in topCategories.take(6))
                          ComparisonBarItem(
                            label: entry.key,
                            primaryValue: entry.value,
                            primaryText: formatPeso(entry.value),
                          ),
                      ],
                    );

              final locationChart = topLocations.isEmpty
                  ? null
                  : ShareSplitChart(
                      key: const ValueKey('inventory-dashboard-location-split'),
                      title: 'Stock Value by Storage Location',
                      subtitle:
                          'FIFO stock capital distribution — Store vs Bodega.',
                      slices: [
                        for (final entry in topLocations)
                          ShareSlice(
                            label: entry.key,
                            value: entry.value,
                            amountText: formatPeso(entry.value),
                          ),
                      ],
                    );

              final hasLeftColumn =
                  categoryChart != null || locationChart != null;
              final leftColumn = Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ?categoryChart,
                  if (categoryChart != null && locationChart != null)
                    const SizedBox(height: AppSpacing.lg),
                  ?locationChart,
                ],
              );

              if (!hasLeftColumn) {
                return healthChart;
              }
              if (constraints.maxWidth < 960) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    leftColumn,
                    const SizedBox(height: AppSpacing.lg),
                    healthChart,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: leftColumn),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(flex: 2, child: healthChart),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.lg),
          // 4. Real Active FIFO Pipeline Queue
          InventoryFifoPipelineCard(inventory: inventory),
          const SizedBox(height: AppSpacing.lg),
          if (restockRows.isNotEmpty) ...[
            StockCoverageChart(
              key: const ValueKey('inventory-dashboard-stock-coverage'),
              title: 'Urgent replenishment coverage',
              items: [
                for (final row in restockRows.take(5))
                  StockCoverageItem(row.item, row.onHand, row.threshold),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          // 5. Urgent Restock Queue + Waiting to Receive
          LayoutBuilder(
            builder: (context, constraints) {
              final restock = _restockPanel(inventory);
              final waiting = _waitingPanel(context, purchases);
              if (constraints.maxWidth < _twoColumnWidth) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    restock,
                    const SizedBox(height: AppSpacing.xl),
                    waiting,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: restock),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(flex: 2, child: waiting),
                ],
              );
            },
          ),
          const SizedBox(height: AppSpacing.xl),
          _adjustmentsPanel(inventory, itemNames),
        ],
      ],
    );

    // When hosted inside a bounded-height Scaffold (e.g. standalone widget
    // tests) without an outer scrollable shell, wrap in SingleChildScrollView
    // so vertical content never overflows. Inside InventorySkeletonLayout
    // (which already scrolls and passes unbounded height), return directly.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.hasBoundedHeight) {
          return SingleChildScrollView(child: content);
        }
        return content;
      },
    );
  }

  Widget _restockPanel(InventoryViewmodel inventory) =>
      buildInventoryRestockPanel(context, inventory);

  Widget _waitingPanel(
    BuildContext context,
    SuppliersPurchasesViewmodel purchases,
  ) => buildInventoryWaitingPanel(context, purchases);

  Widget _adjustmentsPanel(
    InventoryViewmodel inventory,
    Map<int, String> itemNames,
  ) {
    final newest = [...inventory.adjustments]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    return InventoryRecentAdjustmentsPanel(
      rows: [
        for (final adjustment in newest.take(_dashboardRowLimit))
          InventoryAdjustmentRow(
            adjustment: adjustment,
            item: itemNames[adjustment.variantId] ?? 'Unknown item',
          ),
      ],
      emptyMessage: 'No adjustments recorded yet.',
      onViewAll: () => context.go(AppRoutes.inventoryStockMovements),
      onRowTap: (_) => context.go(AppRoutes.inventoryStockMovements),
    );
  }
}
