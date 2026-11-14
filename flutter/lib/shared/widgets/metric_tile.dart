import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/shared/widgets/app_panel.dart';
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

  Color get _trendColor {
    final text = trend;
    if (text == null) return AppColors.textSecondary;
    if (text.startsWith('-')) return AppColors.errorText;
    if (text.startsWith('+')) return AppColors.successText;
    return AppColors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final note = caption;
    return AppPanel(
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
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              if (trend != null)
                Text(
                  trend!,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _trendColor,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontFamily: AppTextStyles.cinzelFont,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
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
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
