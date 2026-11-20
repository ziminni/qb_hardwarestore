import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/sales.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:flutter/material.dart';

class SalesRevenueTrend extends StatelessWidget {
  const SalesRevenueTrend({super.key, required this.sales});

  final List<InventorySale> sales;

  @override
  Widget build(BuildContext context) {
    final totals = <DateTime, double>{};
    final counts = <DateTime, int>{};
    for (final sale in sales) {
      if (sale.status != InventorySaleStatus.completed) continue;
      final day = DateUtils.dateOnly(sale.date);
      totals.update(
        day,
        (total) => total + sale.total,
        ifAbsent: () => sale.total,
      );
      counts.update(day, (count) => count + 1, ifAbsent: () => 1);
    }
    if (totals.isEmpty) {
      return const AppPanel(
        title: 'Sales trend',
        child: Text('No completed sales in the loaded records.'),
      );
    }

    final latest = totals.keys.reduce((a, b) => a.isAfter(b) ? a : b);
    final days = List.generate(
      7,
      (index) => DateTime(latest.year, latest.month, latest.day - 6 + index),
    );
    final sevenDayTotal = days.fold<double>(
      0,
      (sum, day) => sum + (totals[day] ?? 0),
    );
    final theme = Theme.of(context);

    Widget cell(String text, {bool heading = false, bool end = false}) =>
        Padding(
          padding: const EdgeInsets.symmetric(
            vertical: AppSpacing.xs,
            horizontal: AppSpacing.xs,
          ),
          child: Text(
            text,
            textAlign: end ? TextAlign.end : TextAlign.start,
            style: heading
                ? theme.textTheme.labelMedium
                : theme.textTheme.bodyMedium,
          ),
        );

    return AppPanel(
      title: 'Sales trend',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Seven-day total', style: theme.textTheme.labelMedium),
          Text(formatPeso(sevenDayTotal), style: theme.textTheme.headlineSmall),
          const SizedBox(height: AppSpacing.sm),
          Table(
            border: TableBorder(
              horizontalInside: BorderSide(color: theme.dividerColor),
            ),
            columnWidths: const {
              0: FlexColumnWidth(1),
              1: FlexColumnWidth(1.4),
              2: FlexColumnWidth(1.6),
            },
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                children: [
                  cell('Day', heading: true),
                  cell('Completed sales', heading: true, end: true),
                  cell('Sales total', heading: true, end: true),
                ],
              ),
              for (final day in days)
                TableRow(
                  children: [
                    cell('${day.month}/${day.day}'),
                    cell('${counts[day] ?? 0}', end: true),
                    cell(formatPeso(totals[day] ?? 0), end: true),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
