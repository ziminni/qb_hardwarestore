import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/features/dashboard/widget/inventory_action_button.dart';
import 'package:client/features/dashboard/widget/inventory_recent_adjustments_panel.dart';
import 'package:client/features/dashboard/widget/inventory_restock_queue_panel.dart';
import 'package:client/features/dashboard/widget/inventory_waiting_to_receive_panel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/routes/routes.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/metric_tile.dart';
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
///
/// The inventory TABLE this page used to show is gone: it repeated the Stock
/// page row for row. What replaces it is the restock queue (ranked, the thing
/// this role is for), the deliveries still owed, and the recent adjustments.
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
Widget buildInventoryRestockPanel(
  BuildContext context,
  InventoryViewmodel inventory,
) {
  final needsRestock =
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

    // Adjustment rows name the item, which the adjustment itself does not carry.
    final itemNames = <int, String>{
      for (final record in inventory.stockRecords)
        record.variant.id:
            '${record.product.baseName} ${record.variant.variantName}',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Inventory overview',
                style: TextStyle(
                  fontFamily: AppTextStyles.cinzelFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // Decision D-04: "Export" is GONE (no export endpoint exists in the
            // client or the API). "Add product" goes to the live Products page
            // instead of doing nothing.
            InventoryActionButton(
              label: 'Add product',
              onPressed: () => context.go(AppRoutes.inventoryProducts),
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
          MetricGrid(
            // Four across at 1440, two at 760: 220 px min would fit three at
            // 760 and leave the fourth tile alone on its own row.
            minTileWidth: 240,
            children: [
              MetricTile(
                label: 'Total products',
                value: formatCount(inventory.products.length),
                caption: 'In the catalogue',
              ),
              MetricTile(
                label: 'Inventory value',
                value: formatPeso(inventoryValue),
                caption: 'On hand at landed cost',
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
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          LayoutBuilder(
            builder: (context, constraints) {
              final restock = _restockPanel(inventory);
              final waiting = _waitingPanel(context, purchases);
              // Two columns only where the LEFT one is still wide enough for
              // DataPanel's 720 px table: at 1440 the content column is about
              // 1,136 px, and a 3:2 split puts both tables under the breakpoint,
              // so both panels would render as boxed cards inside boxed panels
              // and the page would be twice as tall for the same five rows.
              // Below this width the panels stack and each table gets the page.
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
                  // The queue is the page's reason to exist, so it gets the
                  // wider column.
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
