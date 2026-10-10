import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/sales.dart';
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
    return Container(
      height: 270,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Top-selling products',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text('Ranked by completed-sales revenue'),
          const Divider(height: AppSpacing.xl),
          Expanded(
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
                                  '${product.value.quantity.toStringAsFixed(0)} sold',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₱${product.value.revenue.toStringAsFixed(2)}',
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
