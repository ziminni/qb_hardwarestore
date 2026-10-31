import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:client/shared/widgets/empty_state.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/metric_grid.dart';
import 'package:client/shared/widgets/metric_tile.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The stocker's Reports tab (decision D4): the stock numbers this role can
/// already read, plus one line saying what it cannot read.
///
/// Every `/api/v1/reports/*` endpoint is `IsManagerRole`-gated, so a stocker
/// would get a 403 there. The page therefore calls NO reports endpoint: the
/// value and the counts below are derived from the same `InventoryViewmodel`
/// the stock screens render, so the screen can never disagree with them, and no
/// number here is invented. (The dashboard derives them the same way.)
///
/// The lock screen this page used to be led nowhere in the menu: a whole screen
/// that only said "ask someone else". The footnote keeps that truth without
/// spending the screen on it.
class InventoryReportsPage extends StatefulWidget {
  const InventoryReportsPage({super.key});

  @override
  State<InventoryReportsPage> createState() => _InventoryReportsPageState();
}

class _InventoryReportsPageState extends State<InventoryReportsPage> {
  @override
  void initState() {
    super.initState();
    // The store is app-scoped and shared with the stock screens, so a visit
    // after one of them has loaded is free. `hasLoaded` guards it: `load()`
    // notifies synchronously, so it is deferred past the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final inventory = context.read<InventoryViewmodel>();
      if (!inventory.hasLoaded) inventory.load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final inventory = context.watch<InventoryViewmodel>();
    final failure = inventory.loadError;
    final pending = inventory.isLoading || !inventory.hasLoaded;

    final statuses = [
      for (final record in inventory.stockRecords)
        inventory.statusForVariant(record.variant.id),
    ];
    final lowStock = statuses
        .where((status) => status == InventoryStockStatus.lowStock)
        .length;
    final outOfStock = statuses
        .where((status) => status == InventoryStockStatus.outOfStock)
        .length;
    // On hand x landed cost, the same derivation the dashboard prices stock
    // with. Nothing is seeded: an empty batch list reads as zero because the
    // server really sent no lots.
    final value = inventory.batches.fold<double>(
      0,
      (sum, batch) => sum + batch.currentQty * batch.unitCostLanded,
    );

    return InventorySkeletonLayout(
      title: 'Reports',
      subtitle: 'Stock value and stock alerts from the inventory data.',
      selectedNavigationIndex: 11,
      onNavigationSelected: (index) => navigateInventory(context, index),
      child: pending && !inventory.hasLoaded
          ? const Center(child: CircularProgressIndicator())
          // A failed FIRST load says one thing: the read failed and can be
          // retried. Painting ₱0.00 under it would read as "the store holds
          // nothing", which is the lie this page exists to avoid.
          : failure != null && inventory.products.isEmpty
          ? ErrorBanner(message: failure, onRetry: inventory.load)
          : inventory.products.isEmpty
          ? const EmptyState(
              icon: Icons.inventory_2_outlined,
              message: 'No stock records yet.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A failed refresh keeps the figures below and says above them
                // that they are the last good read.
                if (failure != null) ...[
                  ErrorBanner(message: failure, onRetry: inventory.load),
                  const SizedBox(height: AppSpacing.md),
                ],
                _Overview(
                  value: value,
                  lowStock: lowStock,
                  outOfStock: outOfStock,
                  productCount: inventory.products.length,
                  variantCount: statuses.length,
                ),
                const SizedBox(height: AppSpacing.md),
                const AppPanel(
                  title: 'Manager reports',
                  child: Text(
                    'Sales, profit and audit reports are available to Store '
                    'Managers and above. Ask your manager for a summary.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// The four stock figures, laid out by [MetricGrid] so they fit the width they
/// are given (four across on a wide window, two at 760 px) instead of being
/// squeezed into a hand-built row.
class _Overview extends StatelessWidget {
  const _Overview({
    required this.value,
    required this.lowStock,
    required this.outOfStock,
    required this.productCount,
    required this.variantCount,
  });

  final double value;
  final int lowStock;
  final int outOfStock;
  final int productCount;
  final int variantCount;

  @override
  Widget build(BuildContext context) {
    final tiles = [
      MetricTile(
        key: const ValueKey('reports-inventory-value'),
        label: 'INVENTORY VALUE',
        value: formatPeso(value),
        caption: 'Landed cost of stock on hand',
      ),
      MetricTile(
        key: const ValueKey('reports-low-stock'),
        label: 'LOW STOCK',
        value: formatCount(lowStock),
        caption: 'Below the reorder level',
      ),
      MetricTile(
        key: const ValueKey('reports-out-of-stock'),
        label: 'OUT OF STOCK',
        value: formatCount(outOfStock),
        caption: 'Nothing on hand',
      ),
      MetricTile(
        key: const ValueKey('reports-products'),
        label: 'PRODUCTS COUNTED',
        value: formatCount(productCount),
        caption: '${formatCount(variantCount)} product variants',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Four tiles in a row when four comfortable ones fit, otherwise two:
        // an in-between minimum leaves the fourth tile stranded on its own line.
        final width = constraints.maxWidth;
        final minTileWidth = width >= 4 * 235 + 36 ? 235.0 : (width - 12) / 2;
        return MetricGrid(minTileWidth: minTileWidth, children: tiles);
      },
    );
  }
}
