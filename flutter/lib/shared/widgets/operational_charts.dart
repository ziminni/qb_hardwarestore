import 'dart:math' as math;

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/tender_method.dart';
import 'package:client/shared/widgets/analytics_charts.dart';
import 'package:flutter/material.dart';

/// Allocation of the complete invoice value, not merely cleared cash. The
/// backend includes change-adjusted tenders and unpaid on-account amounts.
class PaymentAllocationChart extends StatelessWidget {
  const PaymentAllocationChart({
    super.key,
    required this.amounts,
    required this.title,
  });
  final Map<String, double> amounts;
  final String title;

  @override
  Widget build(BuildContext context) {
    final sorted = amounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = sorted.fold<double>(0, (sum, entry) => sum + entry.value);
    if (sorted.any((entry) => entry.value < 0)) {
      return AnalyticsCard(
        title: title,
        subtitle: 'Signed amounts cannot be drawn as shares of a whole.',
        child: Column(
          children: [
            for (final entry in sorted)
              ListTile(
                title: Text(TenderMethod.labelFor(entry.key)),
                trailing: Text(formatPeso(entry.value)),
              ),
          ],
        ),
      );
    }
    return DonutChart(
      title: title,
      subtitle:
          'Invoice allocation after cash change, including on-account sales. Not cash intake.',
      centerLabel: 'Invoice total',
      centerValue: formatPeso(total),
      slices: [
        for (final entry in sorted)
          ShareSlice(
            label: TenderMethod.labelFor(entry.key),
            value: entry.value,
            amountText: formatPeso(entry.value),
          ),
      ],
    );
  }
}

/// An inventory bullet plot: the filled amount is stock on hand, the vertical
/// marker is the minimum required stock. A shared scale per item makes the
/// remaining fraction meaningful even when products use different units.
class StockCoverageItem {
  const StockCoverageItem(this.label, this.onHand, this.minimum);
  final String label;
  final double onHand;
  final double minimum;
}

class StockCoverageChart extends StatelessWidget {
  const StockCoverageChart({
    super.key,
    required this.items,
    this.title = 'Stock coverage against minimum',
  });
  final List<StockCoverageItem> items;
  final String title;

  @override
  Widget build(BuildContext context) => AnalyticsCard(
    title: title,
    subtitle:
        'On-hand quantity versus minimum stock for each item. The dark marker is the minimum.',
    child: Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: _CoverageRow(item),
          ),
      ],
    ),
  );
}

class _CoverageRow extends StatelessWidget {
  const _CoverageRow(this.item);
  final StockCoverageItem item;

  @override
  Widget build(BuildContext context) {
    final maximum = math.max(1.0, math.max(item.onHand, item.minimum));
    final ratio = item.minimum > 0 ? item.onHand / item.minimum : null;
    final color = item.onHand <= 0
        ? AppColors.error
        : item.onHand < item.minimum
        ? AppColors.warning
        : AppColors.brandGold;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${formatQuantity(item.onHand)} / ${formatQuantity(item.minimum)}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Semantics(
          label:
              '${item.label}, on hand ${formatQuantity(item.onHand)}, minimum ${formatQuantity(item.minimum)}',
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return SizedBox(
                height: 15,
                child: Stack(
                  children: [
                    Positioned.fill(
                      top: 3,
                      bottom: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: AppColors.surfaceSunken,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 3,
                      bottom: 3,
                      width: width * (item.onHand / maximum).clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    if (item.minimum > 0)
                      Positioned(
                        left: (width * item.minimum / maximum - 1).clamp(
                          0.0,
                          math.max(0.0, width - 2),
                        ),
                        top: 0,
                        bottom: 0,
                        width: 2,
                        child: const ColoredBox(color: AppColors.brandBlack),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          ratio == null
              ? 'No positive minimum configured'
              : '${(ratio * 100).toStringAsFixed(0)}% of minimum',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Diverging, zero-centred bar chart preserves the direction of corrections.
class SignedVarianceItem {
  const SignedVarianceItem(this.label, this.value);
  final String label;
  final double value;
}

class SignedVarianceChart extends StatelessWidget {
  const SignedVarianceChart({
    super.key,
    required this.items,
    required this.title,
    required this.subtitle,
  });
  final List<SignedVarianceItem> items;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scale = items.fold<double>(
      1,
      (previous, item) => math.max(previous, item.value.abs()),
    );
    return AnalyticsCard(
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Decrease',
                style: TextStyle(color: AppColors.errorText, fontSize: 11),
              ),
              Text('0', style: TextStyle(fontSize: 11)),
              Text(
                'Increase',
                style: TextStyle(color: AppColors.successText, fontSize: 11),
              ),
            ],
          ),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(formatSignedQuantity(item.value)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final center = constraints.maxWidth / 2;
                      final bar = center * item.value.abs() / scale;
                      return SizedBox(
                        height: 14,
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceSunken,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                            Positioned(
                              left: item.value < 0 ? center - bar : center,
                              width: bar,
                              top: 2,
                              bottom: 2,
                              child: ColoredBox(
                                color: item.value < 0
                                    ? AppColors.error
                                    : AppColors.success,
                              ),
                            ),
                            Positioned(
                              left: center - .5,
                              width: 1,
                              top: 0,
                              bottom: 0,
                              child: const ColoredBox(
                                color: AppColors.brandBlack,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// FIFO age composition by product, keeping actual quantity values visible.
class FifoAgeItem {
  const FifoAgeItem(this.label, this.fresh, this.aging, this.old);
  final String label;
  final double fresh;
  final double aging;
  final double old;
}

class FifoAgeChart extends StatelessWidget {
  const FifoAgeChart({super.key, required this.items});
  final List<FifoAgeItem> items;

  @override
  Widget build(BuildContext context) => AnalyticsCard(
    title: 'FIFO priority by item',
    subtitle:
        'Oldest batches first. Each stacked bar represents the age composition of that item, not a comparison of unit types.',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Text('0–30 days', style: TextStyle(color: AppColors.successText)),
            Text(
              '31–90 days',
              style: TextStyle(color: AppColors.brandGoldText),
            ),
            Text('90+ days', style: TextStyle(color: AppColors.errorText)),
          ],
        ),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: _FifoAgeRow(item),
          ),
      ],
    ),
  );
}

class _FifoAgeRow extends StatelessWidget {
  const _FifoAgeRow(this.item);
  final FifoAgeItem item;
  @override
  Widget build(BuildContext context) {
    final values = [item.fresh, item.aging, item.old];
    const colors = [AppColors.success, AppColors.brandGold, AppColors.error];
    final total = values.fold<double>(
      0,
      (sum, value) => sum + math.max(0, value),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(item.label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              height: 13,
              child: total <= 0
                  ? const ColoredBox(color: AppColors.surfaceSunken)
                  : Row(
                      children: [
                        for (var i = 0; i < values.length; i++)
                          if (values[i] > 0)
                            SizedBox(
                              width: constraints.maxWidth * values[i] / total,
                              child: ColoredBox(color: colors[i]),
                            ),
                      ],
                    ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Fresh ${formatQuantity(item.fresh)}  •  Aging ${formatQuantity(item.aging)}  •  Old ${formatQuantity(item.old)}',
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
