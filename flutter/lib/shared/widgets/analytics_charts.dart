import 'dart:math' as math;

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/format/format.dart';
import 'package:client/data/models/reports.dart';
import 'package:flutter/material.dart';

/// Card wrapper for analytics charts and profit breakdowns.
class AnalyticsCard extends StatelessWidget {
  const AnalyticsCard({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    required this.child,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

/// Clear, step-by-step operational profit breakdown:
/// Shelf/utang price -> minus discounts -> minus VAT -> minus landed COGS = Gross Profit.
class ProfitBreakdownCard extends StatelessWidget {
  const ProfitBreakdownCard({super.key, required this.sales});

  final SalesSummary sales;

  @override
  Widget build(BuildContext context) {
    final grossMerch = sales.merchandiseGross ?? 0;
    final discounts = sales.totalDiscounts;
    final netMerchInclVat = grossMerch - discounts;
    final netMerchExVat = sales.merchandiseNetExVat ?? sales.totalVatableSales;
    final goodsVat = (netMerchInclVat - netMerchExVat).clamp(
      0.0,
      double.infinity,
    );
    final cogs = sales.totalCogs;
    final profit = sales.grossProfit;
    final marginPct = sales.grossMarginPercent;
    final markupPct = sales.effectiveMarkupPercent;

    return AnalyticsCard(
      key: const ValueKey('profit-breakdown-card'),
      title: 'Operational Profit Breakdown',
      subtitle:
          'Starts from shelf/utang price, deducts discounts & VAT, then subtracts landed batch cost (COGS).',
      trailing: marginPct != null
          ? Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _StatPill(
                  label: 'Margin ${marginPct.toStringAsFixed(1)}%',
                  color: profit != null && profit < 0
                      ? AppColors.error
                      : AppColors.success,
                ),
                if (markupPct != null)
                  _StatPill(
                    label: 'Markup ${markupPct.toStringAsFixed(1)}%',
                    color: AppColors.info,
                  ),
              ],
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!sales.costCoverage.complete) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warningTint,
                borderRadius: BorderRadius.circular(AppRadii.small),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Partial cost history: ${sales.costCoverage.missingCostDeductions} older stock movement(s) predated cost snapshots and are excluded from COGS rather than counted as ₱0.00.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (cogs != null && profit != null && netMerchExVat > 0) ...[
            _ProfitSplitBar(
              cogs: cogs,
              profit: profit,
              discounts: discounts,
              vat: goodsVat,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
          _BreakdownLine(
            label: 'Goods at shelf / utang price (before discounts)',
            amount: formatPeso(grossMerch),
          ),
          _BreakdownLine(
            label: 'Less: Discounts given (line + sale)',
            amount: discounts > 0
                ? '− ${formatPeso(discounts)}'
                : formatPeso(0),
            valueColor: discounts > 0 ? AppColors.warning : null,
          ),
          _BreakdownLine(
            label:
                'Less: VAT on goods (remitted to the tax authority, not profit)',
            amount: goodsVat > 0 ? '− ${formatPeso(goodsVat)}' : formatPeso(0),
            muted: true,
          ),
          const Divider(height: 16),
          _BreakdownLine(
            label: 'Net merchandise sales (ex-VAT)',
            amount: formatPeso(netMerchExVat),
            bold: true,
          ),
          _BreakdownLine(
            label: 'Less: Landed cost of goods sold (FIFO COGS)',
            amount: cogs == null
                ? 'Missing cost history'
                : '− ${formatPeso(cogs)}',
            valueColor: cogs == null
                ? AppColors.warning
                : AppColors.textPrimary,
          ),
          const Divider(height: 16),
          _BreakdownLine(
            label: 'Operational gross profit',
            amount: profit == null ? 'Unavailable' : formatPeso(profit),
            bold: true,
            large: true,
            valueColor: profit == null
                ? AppColors.textSecondary
                : (profit < 0 ? AppColors.error : AppColors.success),
          ),
          if (sales.totalDeliveryFees > 0 || sales.totalPaymentFees > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceSunken,
                borderRadius: BorderRadius.circular(AppRadii.small),
              ),
              child: Text(
                'Kept outside merchandise profit: '
                '${sales.totalDeliveryFees > 0 ? 'Delivery fees ${formatPeso(sales.totalDeliveryFees)}' : ''}'
                '${sales.totalDeliveryFees > 0 && sales.totalPaymentFees > 0 ? ' · ' : ''}'
                '${sales.totalPaymentFees > 0 ? 'Payment fees ${formatPeso(sales.totalPaymentFees)}' : ''}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfitSplitBar extends StatelessWidget {
  const _ProfitSplitBar({
    required this.cogs,
    required this.profit,
    required this.discounts,
    required this.vat,
  });

  final double cogs;
  final double profit;
  final double discounts;
  final double vat;

  @override
  Widget build(BuildContext context) {
    final cogsPos = math.max(0.0, cogs);
    final profitPos = math.max(0.0, profit);
    final discPos = math.max(0.0, discounts);
    final vatPos = math.max(0.0, vat);
    final total = cogsPos + profitPos + discPos + vatPos;
    if (total <= 0) return const SizedBox.shrink();

    int flexOf(double v) => math.max(1, ((v / total) * 1000).round());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.small),
          child: SizedBox(
            height: 16,
            child: Row(
              children: [
                if (cogsPos > 0)
                  Expanded(
                    flex: flexOf(cogsPos),
                    child: Container(color: const Color(0xFF475569)),
                  ),
                if (profitPos > 0)
                  Expanded(
                    flex: flexOf(profitPos),
                    child: Container(color: AppColors.success),
                  ),
                if (discPos > 0)
                  Expanded(
                    flex: flexOf(discPos),
                    child: Container(color: AppColors.warning),
                  ),
                if (vatPos > 0)
                  Expanded(
                    flex: flexOf(vatPos),
                    child: Container(color: AppColors.info),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            if (cogsPos > 0)
              _LegendDot(
                color: const Color(0xFF475569),
                label: 'COGS (${(cogsPos / total * 100).toStringAsFixed(0)}%)',
              ),
            if (profitPos > 0)
              _LegendDot(
                color: AppColors.success,
                label:
                    'Profit (${(profitPos / total * 100).toStringAsFixed(0)}%)',
              ),
            if (discPos > 0)
              _LegendDot(
                color: AppColors.warning,
                label:
                    'Discounts (${(discPos / total * 100).toStringAsFixed(0)}%)',
              ),
            if (vatPos > 0)
              _LegendDot(
                color: AppColors.info,
                label: 'VAT (${(vatPos / total * 100).toStringAsFixed(0)}%)',
              ),
          ],
        ),
      ],
    );
  }
}

class _BreakdownLine extends StatelessWidget {
  const _BreakdownLine({
    required this.label,
    required this.amount,
    this.bold = false,
    this.large = false,
    this.muted = false,
    this.valueColor,
  });

  final String label;
  final String amount;
  final bool bold;
  final bool large;
  final bool muted;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: large ? 14 : 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                color: muted ? AppColors.textSecondary : AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            amount,
            style: TextStyle(
              fontSize: large ? 15 : 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
              color:
                  valueColor ??
                  (muted ? AppColors.textSecondary : AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// One column point for [GroupedBarTrendChart] and [AreaTrendChart].
class TrendPoint {
  const TrendPoint({
    required this.label,
    required this.primary,
    this.secondary,
    this.lineValue,
    this.previous,
  });

  final String label;
  final double primary;
  final double? secondary;
  final double? lineValue;

  /// The dashed comparison a filled chart draws over the same point: the same
  /// slot in the previous period, or another series that is not this one.
  final double? previous;
}

/// Multi-series vertical bar + optional trend line chart rendered via CustomPainter.
class GroupedBarTrendChart extends StatelessWidget {
  const GroupedBarTrendChart({
    super.key,
    required this.title,
    this.subtitle,
    required this.points,
    required this.primaryLabel,
    this.primaryColor = AppColors.primary,
    this.secondaryLabel,
    this.secondaryColor = const Color(0xFF64748B),
    this.lineLabel,
    this.lineColor = AppColors.success,
    this.isCurrency = true,
    this.height = 200,
  });

  final String title;
  final String? subtitle;
  final List<TrendPoint> points;
  final String primaryLabel;
  final Color primaryColor;
  final String? secondaryLabel;
  final Color secondaryColor;
  final String? lineLabel;
  final Color lineColor;
  final bool isCurrency;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    final visible = points.length > 14
        ? points.sublist(points.length - 14)
        : points;
    final hasSecondary =
        secondaryLabel != null && visible.any((p) => p.secondary != null);
    final hasLine =
        lineLabel != null && visible.any((p) => p.lineValue != null);

    double maxVal = 0;
    for (final p in visible) {
      maxVal = math.max(maxVal, p.primary.abs());
      if (p.secondary != null) maxVal = math.max(maxVal, p.secondary!.abs());
      if (p.lineValue != null) maxVal = math.max(maxVal, p.lineValue!.abs());
    }
    if (maxVal <= 0) maxVal = 1;

    String fmtAxis(double v) =>
        isCurrency ? _compactPeso(v) : formatQuantity(v);

    return AnalyticsCard(
      title: title,
      subtitle: subtitle,
      trailing: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          _LegendDot(color: primaryColor, label: primaryLabel),
          if (hasSecondary)
            _LegendDot(color: secondaryColor, label: secondaryLabel!),
          if (hasLine) _LegendDot(color: lineColor, label: lineLabel!),
        ],
      ),
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 58,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      fmtAxis(maxVal),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    Text(
                      fmtAxis(maxVal / 2),
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const Text(
                      '0',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: CustomPaint(
                      painter: _GroupedBarPainter(
                        points: visible,
                        maxVal: maxVal,
                        primaryColor: primaryColor,
                        secondaryColor: secondaryColor,
                        lineColor: lineColor,
                        showSecondary: hasSecondary,
                        showLine: hasLine,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 18,
                    child: Row(
                      children: [
                        for (var i = 0; i < visible.length; i++)
                          Expanded(
                            child: Text(
                              _shouldShowXLabel(i, visible.length)
                                  ? visible[i].label
                                  : '',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _shouldShowXLabel(int index, int total) {
    if (total <= 7) return true;
    return index == 0 || index == total - 1 || index.isEven;
  }
}

class _GroupedBarPainter extends CustomPainter {
  _GroupedBarPainter({
    required this.points,
    required this.maxVal,
    required this.primaryColor,
    required this.secondaryColor,
    required this.lineColor,
    required this.showSecondary,
    required this.showLine,
  });

  final List<TrendPoint> points;
  final double maxVal;
  final Color primaryColor;
  final Color secondaryColor;
  final Color lineColor;
  final bool showSecondary;
  final bool showLine;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = AppColors.border
      ..strokeWidth = 1;

    for (final frac in [0.0, 0.5, 1.0]) {
      final y = size.height * frac;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final slotW = size.width / points.length;
    final barGap = showSecondary ? 3.0 : 0.0;
    final barW = math.min(
      24.0,
      math.max(6.0, (slotW * (showSecondary ? 0.34 : 0.52))),
    );

    final primaryPaint = Paint()..color = primaryColor;
    final negPaint = Paint()..color = AppColors.error;
    final secondaryPaint = Paint()..color = secondaryColor;
    final linePoints = <Offset>[];

    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final centerX = slotW * i + slotW / 2;
      final primaryH = (p.primary.abs() / maxVal) * size.height;

      if (showSecondary) {
        final leftX = centerX - barW - barGap / 2;
        final rect1 = RRect.fromRectAndCorners(
          Rect.fromLTWH(leftX, size.height - primaryH, barW, primaryH),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        );
        canvas.drawRRect(rect1, p.primary < 0 ? negPaint : primaryPaint);

        if (p.secondary != null) {
          final secH = (p.secondary!.abs() / maxVal) * size.height;
          final rightX = centerX + barGap / 2;
          final rect2 = RRect.fromRectAndCorners(
            Rect.fromLTWH(rightX, size.height - secH, barW, secH),
            topLeft: const Radius.circular(3),
            topRight: const Radius.circular(3),
          );
          canvas.drawRRect(rect2, secondaryPaint);
        }
      } else {
        final rect = RRect.fromRectAndCorners(
          Rect.fromLTWH(
            centerX - barW / 2,
            size.height - primaryH,
            barW,
            primaryH,
          ),
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        );
        canvas.drawRRect(rect, p.primary < 0 ? negPaint : primaryPaint);
      }

      if (showLine && p.lineValue != null) {
        final lineH = (p.lineValue!.clamp(0.0, maxVal) / maxVal) * size.height;
        linePoints.add(Offset(centerX, size.height - lineH));
      }
    }

    if (linePoints.isNotEmpty) {
      final linePaint = Paint()
        ..color = lineColor
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke;
      if (linePoints.length > 1) {
        final path = Path()..moveTo(linePoints.first.dx, linePoints.first.dy);
        for (var i = 1; i < linePoints.length; i++) {
          path.lineTo(linePoints[i].dx, linePoints[i].dy);
        }
        canvas.drawPath(path, linePaint);
      }
      final dotPaint = Paint()..color = lineColor;
      for (final pt in linePoints) {
        canvas.drawCircle(pt, 3.5, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _GroupedBarPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.maxVal != maxVal;
}

/// One row for [HorizontalComparisonChart].
class ComparisonBarItem {
  const ComparisonBarItem({
    required this.label,
    required this.primaryValue,
    required this.primaryText,
    this.secondaryValue,
    this.secondaryText,
    this.badgeText,
  });

  final String label;
  final double primaryValue;
  final String primaryText;
  final double? secondaryValue;
  final String? secondaryText;
  final String? badgeText;
}

/// Horizontal single- or dual-bar comparison chart for categories, locations,
/// adjustment types, and requisition statuses.
class HorizontalComparisonChart extends StatelessWidget {
  const HorizontalComparisonChart({
    super.key,
    required this.title,
    this.subtitle,
    required this.items,
    required this.primaryLabel,
    this.primaryColor = AppColors.primary,
    this.secondaryLabel,
    this.secondaryColor = const Color(0xFF64748B),
  });

  final String title;
  final String? subtitle;
  final List<ComparisonBarItem> items;
  final String primaryLabel;
  final Color primaryColor;
  final String? secondaryLabel;
  final Color secondaryColor;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final hasSecondary =
        secondaryLabel != null && items.any((i) => i.secondaryValue != null);

    double maxVal = 0;
    for (final item in items) {
      maxVal = math.max(maxVal, item.primaryValue.abs());
      if (item.secondaryValue != null) {
        maxVal = math.max(maxVal, item.secondaryValue!.abs());
      }
    }
    if (maxVal <= 0) maxVal = 1;

    return AnalyticsCard(
      title: title,
      subtitle: subtitle,
      trailing: Wrap(
        spacing: 10,
        children: [
          _LegendDot(color: primaryColor, label: primaryLabel),
          if (hasSecondary)
            _LegendDot(color: secondaryColor, label: secondaryLabel!),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    items[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (items[i].badgeText != null) ...[
                  const SizedBox(width: 6),
                  _StatPill(label: items[i].badgeText!, color: AppColors.info),
                ],
                const SizedBox(width: 8),
                Text(
                  items[i].secondaryText != null
                      ? '${items[i].primaryText} / ${items[i].secondaryText}'
                      : items[i].primaryText,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            _BarTrack(
              fraction: (items[i].primaryValue.abs() / maxVal).clamp(0.0, 1.0),
              color: primaryColor,
            ),
            if (hasSecondary && items[i].secondaryValue != null) ...[
              const SizedBox(height: 3),
              _BarTrack(
                fraction: (items[i].secondaryValue!.abs() / maxVal).clamp(
                  0.0,
                  1.0,
                ),
                color: secondaryColor,
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// One part of a whole for [ShareSplitChart].
class ShareSlice {
  const ShareSlice({
    required this.label,
    required this.value,
    required this.amountText,
  });

  final String label;
  final double value;

  /// Pre-formatted amount, so Peso formatting stays with the caller.
  final String amountText;
}

/// The palette a composition shares: gold first, then the store's own
/// supporting colours. Blue never appears, so a split reads as this store's.
const List<Color> _sharePalette = [
  AppColors.primary,
  AppColors.success,
  AppColors.warning,
  AppColors.textSecondary,
  AppColors.brandGoldLight,
];

/// A 100% split bar plus a legend: how one total divides into parts (tender
/// methods, deduction kinds). Parts of zero are left out, so a split never
/// grows a bar for money that did not move.
class ShareSplitChart extends StatelessWidget {
  const ShareSplitChart({
    super.key,
    required this.title,
    this.subtitle,
    required this.slices,
  });

  final String title;
  final String? subtitle;
  final List<ShareSlice> slices;

  /// Gold-first, so a split stays in the store's own colours.
  static const List<Color> _palette = _sharePalette;

  @override
  Widget build(BuildContext context) {
    final parts = [
      for (final slice in slices)
        if (slice.value > 0) slice,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    final total = parts.fold<double>(0, (sum, slice) => sum + slice.value);

    int flexOf(double value) => math.max(1, ((value / total) * 1000).round());

    return AnalyticsCard(
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.small),
            child: SizedBox(
              height: 18,
              child: Row(
                children: [
                  for (var i = 0; i < parts.length; i++)
                    Expanded(
                      flex: flexOf(parts[i].value),
                      child: Container(color: _palette[i % _palette.length]),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (var i = 0; i < parts.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  _LegendDot(
                    color: _palette[i % _palette.length],
                    label: parts[i].label,
                  ),
                  const Spacer(),
                  Text(
                    '${parts[i].amountText} · '
                    '${(parts[i].value / total * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _BarTrack extends StatelessWidget {
  const _BarTrack({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Container(
        height: 8,
        color: AppColors.surfaceSunken,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: fraction,
          child: Container(color: color),
        ),
      ),
    );
  }
}

// --- Filled and shaped charts ---------------------------------------------
// The Stitch reports mock reads filled, dashed, stacked and ringed rather than
// as bars: a trend is an area with the comparison behind it, a composition is a
// ring, and hours are a 24-slot area. Colours stay the store's gold and black.

/// A filled area trend with a dashed comparison line over it.
class AreaTrendChart extends StatelessWidget {
  const AreaTrendChart({
    super.key,
    required this.title,
    this.subtitle,
    required this.points,
    required this.valueLabel,
    this.previousLabel,
    this.isCurrency = true,
    this.height = 190,
  });

  final String title;
  final String? subtitle;
  final List<TrendPoint> points;

  /// Name of the filled series in the legend.
  final String valueLabel;

  /// Name of the dashed line. Null, or no point carrying a [TrendPoint.previous],
  /// leaves the chart single-series.
  final String? previousLabel;
  final bool isCurrency;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) return const SizedBox.shrink();
    // Older dates scroll off rather than shrinking to an unreadable sliver.
    final visible = points.length > 20
        ? points.sublist(points.length - 20)
        : points;
    final hasPrevious =
        previousLabel != null && visible.any((p) => p.previous != null);

    var maxVal = 0.0;
    for (final point in visible) {
      maxVal = math.max(maxVal, math.max(point.primary, point.previous ?? 0));
    }
    if (maxVal <= 0) maxVal = 1;

    return AnalyticsCard(
      title: title,
      subtitle: subtitle,
      trailing: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          _LegendSwatch(
            color: AppColors.primary,
            label: valueLabel,
            filled: true,
          ),
          if (hasPrevious)
            _LegendSwatch(color: AppColors.secondary, label: previousLabel!),
        ],
      ),
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AxisColumn(maxValue: maxVal, isCurrency: isCurrency),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: CustomPaint(
                      painter: _AreaTrendPainter(
                        points: visible,
                        maxVal: maxVal,
                        showPrevious: hasPrevious,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _XLabels(labels: [for (final p in visible) p.label]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaTrendPainter extends CustomPainter {
  _AreaTrendPainter({
    required this.points,
    required this.maxVal,
    required this.showPrevious,
  });

  final List<TrendPoint> points;
  final double maxVal;
  final bool showPrevious;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);

    final slope = points.length == 1 ? 0.0 : size.width / (points.length - 1);
    double xOf(int index) =>
        points.length == 1 ? size.width / 2 : slope * index;
    double yOf(double value) =>
        size.height - (value.clamp(0.0, maxVal) / maxVal) * size.height;

    final line = Path();
    for (var i = 0; i < points.length; i++) {
      final point = Offset(xOf(i), yOf(points[i].primary));
      if (i == 0) {
        line.moveTo(point.dx, point.dy);
      } else {
        line.lineTo(point.dx, point.dy);
      }
    }
    final area = Path.from(line)
      ..lineTo(xOf(points.length - 1), size.height)
      ..lineTo(xOf(0), size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withValues(alpha: 0.38),
            AppColors.primary.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (!showPrevious) return;
    // A gap in the comparison starts a new dashed run instead of joining across
    // slots the comparison did not report.
    final dashes = Path();
    var drawing = false;
    for (var i = 0; i < points.length; i++) {
      final previous = points[i].previous;
      if (previous == null) {
        drawing = false;
        continue;
      }
      final point = Offset(xOf(i), yOf(previous));
      if (drawing) {
        dashes.lineTo(point.dx, point.dy);
      } else {
        dashes.moveTo(point.dx, point.dy);
        drawing = true;
      }
    }
    _paintDashed(
      canvas,
      dashes,
      Paint()
        ..color = AppColors.secondary
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _AreaTrendPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.maxVal != maxVal;
}

class StackedSeries {
  const StackedSeries({required this.label, required this.color});

  final String label;
  final Color color;
}

/// One column of a [StackedColumnChart]: the x label and one value per series,
/// in series order. A zero segment draws nothing.
class StackedColumnPoint {
  const StackedColumnPoint({required this.label, required this.values});

  final String label;
  final List<double> values;
}

/// Stacked columns: each bar is one point, split into its series from the
/// bottom up, so the bar's height is the whole and the segments are its parts.
class StackedColumnChart extends StatelessWidget {
  const StackedColumnChart({
    super.key,
    required this.title,
    this.subtitle,
    required this.points,
    required this.series,
    this.valueLabel,
    this.isCurrency = true,
    this.height = 190,
  });

  final String title;
  final String? subtitle;
  final List<StackedColumnPoint> points;
  final List<StackedSeries> series;

  /// What the whole bar measures, named above the legend when it has a name.
  final String? valueLabel;
  final bool isCurrency;
  final double height;

  @override
  Widget build(BuildContext context) {
    // A column with no positive segment has nothing to stack, so it is left out
    // rather than drawn as a flat line of zero height.
    final columns = [
      for (final point in points)
        if (point.values.any((value) => value > 0)) point,
    ];
    if (columns.isEmpty || series.isEmpty) return const SizedBox.shrink();
    final visible = columns.length > 10
        ? columns.sublist(columns.length - 10)
        : columns;

    var maxVal = 0.0;
    for (final column in visible) {
      maxVal = math.max(maxVal, _stackTotal(column));
    }
    if (maxVal <= 0) maxVal = 1;

    return AnalyticsCard(
      title: title,
      subtitle: subtitle,
      trailing: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          for (final entry in series)
            _LegendDot(color: entry.color, label: entry.label),
        ],
      ),
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AxisColumn(maxValue: maxVal, isCurrency: isCurrency),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: CustomPaint(
                      painter: _StackedColumnPainter(
                        points: visible,
                        colors: [for (final entry in series) entry.color],
                        maxVal: maxVal,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _XLabels(
                    labels: [for (final column in visible) column.label],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The whole a column stacks to: its parts, each floored at zero so a
  /// correction never eats the bar it sits in.
  static double _stackTotal(StackedColumnPoint column) =>
      column.values.fold<double>(0, (sum, value) => sum + math.max(0, value));
}

class _StackedColumnPainter extends CustomPainter {
  _StackedColumnPainter({
    required this.points,
    required this.colors,
    required this.maxVal,
  });

  final List<StackedColumnPoint> points;
  final List<Color> colors;
  final double maxVal;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);

    final slotW = size.width / points.length;
    final barW = math.min(26.0, math.max(8.0, slotW * 0.55));

    for (var i = 0; i < points.length; i++) {
      final values = points[i].values;
      final centerX = slotW * i + slotW / 2;
      var bottom = size.height;
      for (var j = 0; j < values.length && j < colors.length; j++) {
        final value = values[j];
        if (value <= 0) continue;
        final height = math.min(value / maxVal * size.height, bottom);
        final rect = Rect.fromLTWH(
          centerX - barW / 2,
          bottom - height,
          barW,
          height,
        );
        final isTop = !values.skip(j + 1).any((value) => value > 0);
        final paint = Paint()..color = colors[j];
        if (isTop) {
          canvas.drawRRect(
            RRect.fromRectAndCorners(
              rect,
              topLeft: const Radius.circular(3),
              topRight: const Radius.circular(3),
            ),
            paint,
          );
        } else {
          canvas.drawRect(rect, paint);
        }
        bottom -= height;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _StackedColumnPainter oldDelegate) =>
      oldDelegate.points != points || oldDelegate.maxVal != maxVal;
}

/// A ring split into [ShareSlice]s, with the total in the middle and a legend
/// beside it: parts of one whole, read as a shape rather than a bar.
class DonutChart extends StatelessWidget {
  const DonutChart({
    super.key,
    required this.title,
    this.subtitle,
    required this.slices,
    required this.centerLabel,
    required this.centerValue,
    this.diameter = 140,
  });

  final String title;
  final String? subtitle;
  final List<ShareSlice> slices;

  /// The words under the number in the middle, e.g. `Tendered`.
  final String centerLabel;

  /// The middle number, already formatted by the caller.
  final String centerValue;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    // A slice of nothing is not a part of the whole: it is left out of the ring
    // and the legend alike.
    final parts = [
      for (final slice in slices)
        if (slice.value > 0) slice,
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    final total = parts.fold<double>(0, (sum, slice) => sum + slice.value);

    return AnalyticsCard(
      title: title,
      subtitle: subtitle,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final ring = SizedBox(
            width: diameter,
            height: diameter,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _DonutPainter(
                      values: [for (final part in parts) part.value],
                      total: total,
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      centerValue,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      centerLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
          final legend = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < parts.length; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _sharePalette[i % _sharePalette.length],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          parts[i].label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${parts[i].amountText} · '
                        '${(parts[i].value / total * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          );
          if (constraints.maxWidth < diameter + 220) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(child: ring),
                const SizedBox(height: AppSpacing.md),
                legend,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ring,
              const SizedBox(width: AppSpacing.md),
              Expanded(child: legend),
            ],
          );
        },
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.values, required this.total});

  final List<double> values;
  final double total;

  static const double _ringWidth = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCircle(
      center: Offset(size.width / 2, size.height / 2),
      radius: (math.min(size.width, size.height) - _ringWidth) / 2,
    );
    // A hair of a gap keeps neighbouring arcs from reading as one band.
    final gap = values.length > 1 ? 0.02 : 0.0;
    var start = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = values[i] / total * 2 * math.pi;
      canvas.drawArc(
        rect,
        start,
        math.max(sweep - gap, 0),
        false,
        Paint()
          ..color = _sharePalette[i % _sharePalette.length]
          ..strokeWidth = _ringWidth
          ..style = PaintingStyle.stroke,
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.total != total;
}

/// The store day as one 24-slot area, with the busiest hour marked.
class TimeOfDayChart extends StatelessWidget {
  const TimeOfDayChart({
    super.key,
    required this.title,
    this.subtitle,
    required this.byHour,
    required this.valueLabel,
    this.isCurrency = true,
    this.height = 190,
  });

  /// Store-local hour (0-23) to its value. Hours the report did not return are
  /// plotted as zero, so the shape is always a full day.
  final Map<int, double> byHour;
  final String title;
  final String? subtitle;
  final String valueLabel;
  final bool isCurrency;
  final double height;

  /// The clock labels under the axis, spread across the 24 slots.
  static const List<int> _labelledHours = [0, 6, 12, 18, 23];

  @override
  Widget build(BuildContext context) {
    // The store day is always 24 slots: an hour the report did not return sold
    // nothing, which is a zero rather than a missing shape.
    final values = [for (var hour = 0; hour < 24; hour++) byHour[hour] ?? 0];
    var peakHour = -1;
    for (var hour = 0; hour < values.length; hour++) {
      if (values[hour] > 0 &&
          (peakHour < 0 || values[hour] > values[peakHour])) {
        peakHour = hour;
      }
    }
    if (peakHour < 0) return const SizedBox.shrink();
    final maxVal = values[peakHour];

    return AnalyticsCard(
      title: title,
      subtitle: subtitle,
      trailing: Wrap(
        spacing: 10,
        runSpacing: 4,
        children: [
          _LegendDot(color: AppColors.primary, label: valueLabel),
          _StatPill(
            label:
                'Peak ${_clockLabel(peakHour)} · '
                '${isCurrency ? formatPeso(maxVal) : formatQuantity(maxVal)}',
            color: AppColors.brandGoldText,
          ),
        ],
      ),
      child: SizedBox(
        height: height,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _AxisColumn(maxValue: maxVal, isCurrency: isCurrency),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: CustomPaint(
                      painter: _TimeOfDayPainter(
                        values: values,
                        maxVal: maxVal,
                        peakHour: peakHour,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 18,
                    child: Row(
                      children: [
                        for (final hour in _labelledHours)
                          Expanded(
                            child: Text(
                              _clockLabel(hour),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeOfDayPainter extends CustomPainter {
  _TimeOfDayPainter({
    required this.values,
    required this.maxVal,
    required this.peakHour,
  });

  final List<double> values;
  final double maxVal;
  final int peakHour;

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);

    final slope = size.width / (values.length - 1);
    double xOf(int hour) => slope * hour;
    double yOf(double value) =>
        size.height - (value.clamp(0.0, maxVal) / maxVal) * size.height;

    final line = Path();
    for (var hour = 0; hour < values.length; hour++) {
      final point = Offset(xOf(hour), yOf(values[hour]));
      if (hour == 0) {
        line.moveTo(point.dx, point.dy);
      } else {
        line.lineTo(point.dx, point.dy);
      }
    }
    final area = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.primary.withValues(alpha: 0.38),
            AppColors.primary.withValues(alpha: 0.02),
          ],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = AppColors.primary
        ..strokeWidth = 2.2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );

    // The busiest hour drops a dashed guide to the floor so the peak is not
    // just the tallest bump on the curve.
    final peak = Offset(xOf(peakHour), yOf(maxVal));
    _paintDashed(
      canvas,
      Path()
        ..moveTo(peak.dx, peak.dy)
        ..lineTo(peak.dx, size.height),
      Paint()
        ..color = AppColors.secondary.withValues(alpha: 0.55)
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(peak, 4.5, Paint()..color = AppColors.secondary);
    canvas.drawCircle(peak, 2.0, Paint()..color = AppColors.brandWhite);
  }

  @override
  bool shouldRepaint(covariant _TimeOfDayPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.maxVal != maxVal ||
      oldDelegate.peakHour != peakHour;
}

void _paintGrid(Canvas canvas, Size size) {
  final paint = Paint()
    ..color = AppColors.border
    ..strokeWidth = 1;
  for (final fraction in const [0.0, 0.5, 1.0]) {
    final y = size.height * fraction;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
  }
}

/// Strokes [path] as dashes: Flutter has no dashed stroke, so each dash is cut
/// out of the path's own metrics.
void _paintDashed(
  Canvas canvas,
  Path path,
  Paint paint, {
  double dash = 5,
  double gap = 4,
}) {
  for (final metric in path.computeMetrics()) {
    var distance = 0.0;
    while (distance < metric.length) {
      final end = math.min(distance + dash, metric.length);
      canvas.drawPath(metric.extractPath(distance, end), paint);
      distance = end + gap;
    }
  }
}

/// A legend entry for a filled chart: a solid block or a dashed line, so the
/// legend says which shape the colour draws.
class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({
    required this.color,
    required this.label,
    this.filled = false,
  });

  final Color color;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: filled ? 9 : 2,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// The value axis the filled charts share: max, half, zero.
class _AxisColumn extends StatelessWidget {
  const _AxisColumn({required this.maxValue, required this.isCurrency});

  final double maxValue;
  final bool isCurrency;

  @override
  Widget build(BuildContext context) {
    String label(double value) =>
        isCurrency ? _compactPeso(value) : formatQuantity(value);
    const style = TextStyle(fontSize: 10, color: AppColors.textSecondary);
    return SizedBox(
      width: 58,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(label(maxValue), style: style),
            Text(label(maxValue / 2), style: style),
            const Text('0', style: style),
          ],
        ),
      ),
    );
  }
}

/// The x labels under a filled chart, thinned out so a long range still reads.
class _XLabels extends StatelessWidget {
  const _XLabels({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final total = labels.length;
    return SizedBox(
      height: 18,
      child: Row(
        children: [
          for (var i = 0; i < total; i++)
            Expanded(
              child: Text(
                _showsLabel(i, total) ? labels[i] : '',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static bool _showsLabel(int index, int total) {
    if (total <= 7) return true;
    return index == 0 || index == total - 1 || index.isEven;
  }
}

/// A store-local hour as a clock label: `14` becomes `2:00 PM`.
String _clockLabel(int hour) {
  final h = hour % 12 == 0 ? 12 : hour % 12;
  return '$h:00 ${hour < 12 ? 'AM' : 'PM'}';
}

String _compactPeso(double value) {
  if (value.abs() >= 1000000) {
    return '₱${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value.abs() >= 1000) {
    return '₱${(value / 1000).toStringAsFixed(1)}k';
  }
  return '₱${value.toStringAsFixed(0)}';
}
