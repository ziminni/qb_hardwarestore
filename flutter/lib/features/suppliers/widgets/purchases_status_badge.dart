import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/data/models/supplier.dart';
import 'package:flutter/material.dart';

class PurchasesStatusBadge extends StatelessWidget {
  const PurchasesStatusBadge({super.key, required this.status});
  final PurchaseStatus status;
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      PurchaseStatus.complete => AppColors.success,
      PurchaseStatus.cancelled => AppColors.error,
      PurchaseStatus.partial => AppColors.warning,
      PurchaseStatus.ordered => AppColors.primary,
      PurchaseStatus.draft => Theme.of(context).colorScheme.outline,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
