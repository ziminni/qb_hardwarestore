import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/dashboard/widget/inventory_action_button.dart';
import 'package:client/features/dashboard/widget/inventory_data_table.dart';
import 'package:client/features/dashboard/widget/inventory_list_item.dart';
import 'package:client/features/dashboard/widget/inventory_metric_card.dart';
import 'package:client/features/dashboard/widget/inventory_section.dart';
import 'package:client/features/sales/widgets/live_load_error_banner.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// Inventory home screen content, wired to live data.
///
/// Decision: every section reads `InventoryViewmodel` — the same derivation
/// the stock screens use (not the alerts endpoint), so this screen can never
/// contradict them about the same row. Mock rows are the viewmodel's initial
/// state, so before the first successful load this shows loading/empty/error
/// — never the bundled fixtures as if they were stock.
class InventoryDashboardContent extends StatelessWidget {
  const InventoryDashboardContent({super.key});

  static String _qty(double value) => value == value.truncateToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<InventoryViewmodel>();

    if (viewmodel.isLoading && !viewmodel.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!viewmodel.hasLoaded && viewmodel.loadError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LiveLoadErrorBanner(
            message: viewmodel.loadError!,
            onRetry: viewmodel.load,
          ),
          const SizedBox(height: 16),
          const Text('No products available.'),
        ],
      );
    }
    if (!viewmodel.hasLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    var lowStock = 0;
    var outOfStock = 0;
    for (final product in viewmodel.products) {
      for (final variant in product.variants) {
        final status = viewmodel.statusForVariant(variant.id);
        if (status.name == 'lowStock') lowStock++;
        if (status.name == 'outOfStock') outOfStock++;
      }
    }
    final value = viewmodel.batches.fold<double>(
      0,
      (sum, batch) => sum + batch.currentQty * batch.unitCostLanded,
    );
    final metrics = [
      ('Total products', '${viewmodel.products.length}'),
      ('Inventory value', '₱${value.toStringAsFixed(2)}'),
      ('Low stock', '$lowStock'),
      ('Out of stock', '$outOfStock'),
    ];

    final tableRows = [
      for (final record in viewmodel.stockRecords)
        [
          '${record.product.baseName} ${record.variant.variantName}',
          record.product.categoryName,
          _qty(viewmodel.stockOnHandFor(record.variant.id)),
          _qty(record.variant.minStockThreshold),
          viewmodel.statusForVariant(record.variant.id).label,
        ],
    ];

    String movementTitle(int variantId) =>
        viewmodel.variantFor(variantId)?.variantName ?? 'Unknown item';
    final movements = viewmodel.movements.take(5).map((movement) {
      final qty = movement.quantityChange;
      final detail = movement.reason.isNotEmpty
          ? movement.reason
          : movement.reference.isNotEmpty
          ? movement.reference
          : movement.type.label;
      return InventoryListItem(
        title: movementTitle(movement.variantId),
        subtitle:
            '${movement.timestamp.month}/${movement.timestamp.day}/${movement.timestamp.year} · $detail',
        trailing: '${qty >= 0 ? '+' : ''}${_qty(qty)}',
      );
    }).toList();

    // Most urgent first: zero stock before low stock, then lowest coverage
    // (on-hand / reorder level). A silent take(5) once hid a zero-stock
    // variant at position 6 while the manager restocked others — the queue
    // says how many more need restocking instead.
    final restockAll = [
      for (final product in viewmodel.products)
        for (final variant in product.variants)
          if (viewmodel.statusForVariant(variant.id).name != 'inStock')
            (
              product: product,
              variant: variant,
              onHand: viewmodel.stockOnHandFor(variant.id),
            ),
    ]..sort((a, b) {
      final aOut = a.onHand <= 0;
      final bOut = b.onHand <= 0;
      if (aOut != bOut) return aOut ? -1 : 1;
      double coverage(double onHand, double threshold) =>
          threshold > 0 ? onHand / threshold : 0;
      return coverage(
        a.onHand,
        a.variant.minStockThreshold,
      ).compareTo(coverage(b.onHand, b.variant.minStockThreshold));
    });
    final restock = [
      for (final entry in restockAll.take(5))
        InventoryListItem(
          title: '${entry.product.baseName} ${entry.variant.variantName}',
          subtitle:
              '${_qty(entry.onHand)} on hand · reorder at ${_qty(entry.variant.minStockThreshold)}',
          trailing: viewmodel
              .statusForVariant(entry.variant.id)
              .label,
        ),
      if (restockAll.length > 5)
        InventoryListItem(
          title: '+${restockAll.length - 5} more need restocking',
          subtitle: 'Open the stock list to see all',
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Inventory overview',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            // Decision D-04: "Export" is GONE. No export endpoint exists in the
            // client or the API, so the button could never work — and
            // `InventoryActionButton` defaults `onPressed` to `() {}`, which
            // rendered it as a live-looking dead control. "Add product" goes to
            // the live Products page instead of doing nothing.
            InventoryActionButton(
              label: 'Add product',
              onPressed: () => context.go(AppRoutes.inventoryProducts),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (viewmodel.loadError != null)
          LiveLoadErrorBanner(
            message: viewmodel.loadError!,
            onRetry: viewmodel.load,
          ),
        if (viewmodel.loadError != null) const SizedBox(height: 16),
        if (viewmodel.products.isEmpty)
          const Text('No products available.')
        else ...[
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final metric in metrics)
                SizedBox(
                  width: 190,
                  child: InventoryMetricCard(
                    label: metric.$1,
                    value: metric.$2,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          InventorySection(
            title: 'Inventory table',
            actionLabel: 'Search / Filter',
            child: InventoryDataTable(
              columns: const [
                'Product',
                'Category',
                'On hand',
                'Reorder level',
                'Status',
              ],
              rows: tableRows,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: InventorySection(
                  title: 'Recent stock movements',
                  child: Column(
                    children: movements.isEmpty
                        ? [const Text('No movements recorded.')]
                        : movements,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: InventorySection(
                  title: 'Restock queue',
                  child: Column(
                    children: restock.isEmpty
                        ? [const Text('Nothing to restock.')]
                        : restock,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
