import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:flutter/material.dart';

class SalesTopProducts extends StatelessWidget {
  const SalesTopProducts({super.key, required this.sales});

  final List<InventorySale> sales;

  @override
  Widget build(BuildContext context) {
    final totals = <String, ({double quantity, double revenue})>{};
    for (final sale in sales.where(
      (item) => item.status == InventorySaleStatus.completed,
    )) {
      for (final line in sale.lines) {
        final previous = totals[line.productName];
        totals[line.productName] = (
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
                                  product.key,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${formatCount(product.value.quantity.round())} sold',
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
