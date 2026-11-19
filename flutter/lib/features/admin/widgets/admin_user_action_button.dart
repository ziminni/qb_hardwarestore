import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

/// Primary action button for User Management, driven entirely by its callback.
///
/// `onPressed` is passed straight through: a caller who supplies no callback
/// gets a **disabled** button, which Flutter renders as such. The old
/// `onPressed ?? () {}` default produced an enabled button that swallowed the
/// press and did nothing — the dead-control shape removed in Phase 3 Task 0.
class AdminUserActionButton extends StatelessWidget {
  const AdminUserActionButton({
    super.key,
    required this.label,
    this.icon = Icons.add,
    this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final bg = p.isDark ? p.accent : AppColors.brandBlack;
    final fg = p.isDark ? p.onAccent : AppColors.brandWhite;

    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: onPressed == null ? p.surfaceSunken : bg,
        foregroundColor: onPressed == null ? p.textSecondary : fg,
        disabledBackgroundColor: p.surfaceSunken,
        disabledForegroundColor: p.textSecondary,
        side: BorderSide(color: onPressed == null ? p.border : bg),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        minimumSize: const Size(0, 42),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
        textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      icon: Icon(icon, size: 17),
      label: Text(label),
    );
  }
}
