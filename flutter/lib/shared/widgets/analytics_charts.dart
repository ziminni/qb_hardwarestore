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
    final goodsVat = (netMerchInclVat - netMerchExVat).clamp(0.0, double.infinity);
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
            amount: discounts > 0 ? '− ${formatPeso(discounts)}' : formatPeso(0),
            valueColor: discounts > 0 ? AppColors.warning : null,
          ),
          _BreakdownLine(
            label: 'Less: VAT on goods (remitted to BIR, not profit)',
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
            amount: cogs == null ? 'Missing cost history' : '− ${formatPeso(cogs)}',
            valueColor: cogs == null ? AppColors.warning : AppColors.textPrimary,
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

/// One column point for [GroupedBarTrendChart].
class TrendPoint {
  const TrendPoint({
    required this.label,
    required this.primary,
    this.secondary,
    this.lineValue,
  });

  final String label;
  final double primary;
  final double? secondary;
  final double? lineValue;
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

String _compactPeso(double value) {
  if (value.abs() >= 1000000) {
    return '₱${(value / 1000000).toStringAsFixed(1)}M';
  }
  if (value.abs() >= 1000) {
    return '₱${(value / 1000).toStringAsFixed(1)}k';
  }
  return '₱${value.toStringAsFixed(0)}';
}
