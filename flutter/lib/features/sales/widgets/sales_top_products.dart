import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/catalogue_item.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SalesTopProducts extends StatelessWidget {
  const SalesTopProducts({super.key, required this.sales});

  final List<InventorySale> sales;

  @override
  Widget build(BuildContext context) {
    // The sales wire carries the selling unit's ID and CODE, never a product or
    // variant name (`SalesItemSerializer`), so the name is read from the
    // app-scoped catalogue — the same source the quotation and order sheets
    // resolve against (decision D-02) — and a row falls back to the code when
    // that catalogue has not been read. Nothing here invents a name.
    final catalogue =
        context.watch<InventoryViewmodel?>()?.catalogue ??
        const <CatalogueItem>[];
    final names = <int, String>{
      for (final item in catalogue) item.uom.id: item.displayName,
    };

    // Grouped by selling unit, not by its code: two products sold by the piece
    // both read "PC", and merging them would report one made-up seller.
    final totals = <int, ({String code, double quantity, double revenue})>{};
    for (final sale in sales.where(
      (item) => item.status == InventorySaleStatus.completed,
    )) {
      for (final line in sale.lines) {
        final previous = totals[line.variantUomId];
        totals[line.variantUomId] = (
          code: previous?.code ?? line.sku,
          quantity: (previous?.quantity ?? 0) + line.quantity,
          revenue: (previous?.revenue ?? 0) + line.subtotal,
        );
      }
    }
    final products = totals.entries.toList()
      ..sort((a, b) => b.value.revenue.compareTo(a.value.revenue));
    // The ranked list scrolls inside a bounded box, so the panel sizes to its
    // content and five products never stretch the page.
    return AppPanel(
      title: 'Top-selling products',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ranked by completed-sales revenue'),
          const Divider(height: AppSpacing.xl),
          SizedBox(
            height: 170,
            child: products.isEmpty
                ? const Center(child: Text('No completed sales yet.'))
                : ListView.separated(
                    itemCount: products.take(4).length,
                    separatorBuilder: (_, _) => const Divider(height: 16),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      final name = names[product.key];
                      final sold = formatCount(product.value.quantity.round());
                      return Row(
                        children: [
                          CircleAvatar(
                            radius: 14,
                            backgroundColor: AppColors.selected,
                            child: Text('${index + 1}'),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name ?? product.value.code,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                // With a name above, the code sits here as the
                                // muted second line; without one the code IS the
                                // title, so repeating it would say nothing.
                                Text(
                                  name == null
                                      ? '$sold sold'
                                      : '${product.value.code} · $sold sold',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            formatPeso(product.value.revenue),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
