import 'package:client/core/constants/app_colors.dart';
import 'package:client/shared/widgets/stitch_ui.dart';
import 'package:flutter/material.dart';

/// One dashboard number.
///
/// Lay tiles out with `MetricGrid`, never by hand: it fits as many tiles per
/// line as the width allows (four across at 1440 px, two at 760 px) instead of
/// squeezing each tile into a fixed 260 or 300 px box.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.trend,
  });

  final String label;

  /// Already formatted by the caller (money through `formatPeso`).
  final String value;

  /// What the number counts, e.g. "26 transactions".
  final String? caption;

  /// Change since the previous period, e.g. "-2.1%". The sign picks the color.
  final String? trend;

  StitchTone get _trendTone {
    final text = trend;
    if (text == null) return StitchTone.neutral;
    if (text.startsWith('-')) return StitchTone.danger;
    if (text.startsWith('+')) return StitchTone.success;
    return StitchTone.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final note = caption;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: StitchColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: StitchColors.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: StitchColors.inkMuted,
                  ),
                ),
              ),
              if (trend != null) ...[
                const SizedBox(width: 6),
                StitchPill(label: trend!, tone: _trendTone),
              ],
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
                color: StitchColors.ink,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (note != null) ...[
            const SizedBox(height: 4),
            Text(
              note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
