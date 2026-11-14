import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:flutter/material.dart';

/// The one status pill for the whole app.
///
/// Always words plus color: the label is the message, the tint is the hint. A
/// color alone is unreadable for a color blind user and unprintable in a report.
enum StatusTone { success, warning, error, info, neutral }

/// Gold dark enough to read on a light tint. The brand gold is a fill color and
/// is under 3:1 on cream, so text uses this shade.
const Color _goldInk = Color(0xFF6E5A22);

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.label,
    this.tone = StatusTone.neutral,
  });

  final String label;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (tone) {
      StatusTone.success => (AppColors.successTint, AppColors.successText),
      StatusTone.warning => (AppColors.warningTint, AppColors.warningText),
      StatusTone.error => (AppColors.errorTint, AppColors.errorText),
      StatusTone.info => (AppColors.selected, _goldInk),
      StatusTone.neutral => (AppColors.background, AppColors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        // Neutral has no tint of its own, so it leans on a border to read as a
        // pill instead of loose text.
        border: tone == StatusTone.neutral
            ? Border.all(color: AppColors.border)
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
