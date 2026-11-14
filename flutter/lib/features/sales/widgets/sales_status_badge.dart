import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:flutter/material.dart';

class SalesStatusBadge extends StatelessWidget {
  const SalesStatusBadge({super.key, required this.label, required this.tone});
  final String label;
  final String tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      'success' => AppColors.success,
      'warning' => AppColors.warning,
      'error' => AppColors.error,
      'info' => AppColors.info,
      _ => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
