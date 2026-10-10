import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/data/models/sales.dart';
import 'package:flutter/material.dart';

class SalesRevenueTrend extends StatelessWidget {
  const SalesRevenueTrend({super.key, required this.sales});

  final List<InventorySale> sales;

  @override
  Widget build(BuildContext context) {
    final completed = sales
        .where((sale) => sale.status == InventorySaleStatus.completed)
        .toList();
    final dates = completed.map((sale) => sale.date).toList()..sort();
    final lastDate = dates.isEmpty ? DateTime.now() : dates.last;
    final days = List.generate(
      7,
      (index) =>
          DateTime(lastDate.year, lastDate.month, lastDate.day - (6 - index)),
    );
    final values = days
        .map(
          (day) => completed
              .where(
                (sale) =>
                    sale.date.year == day.year &&
                    sale.date.month == day.month &&
                    sale.date.day == day.day,
              )
              .fold<double>(0, (sum, sale) => sum + sale.total),
        )
        .toList();
    final highest = values.fold<double>(
      0,
      (value, item) => item > value ? item : value,
    );
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
            'Sales trend',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          const Text('Completed sales over the latest seven-day period'),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var index = 0; index < days.length; index++) ...[
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          values[index] == 0
                              ? '—'
                              : '₱${(values[index] / 1000).toStringAsFixed(1)}k',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Flexible(
                          child: FractionallySizedBox(
                            heightFactor: highest == 0
                                ? .05
                                : (values[index] / highest).clamp(.05, 1),
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: 28,
                              decoration: BoxDecoration(
                                color: AppColors.brandGold,
                                borderRadius: BorderRadius.circular(
                                  AppRadii.small,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          '${days[index].month}/${days[index].day}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  if (index < days.length - 1)
                    const SizedBox(width: AppSpacing.sm),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
