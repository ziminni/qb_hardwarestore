import 'package:client/core/constants/app_colors.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/shared/widgets/status_pill.dart';
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
      PurchaseStatus.draft => AppColors.textSecondary,
    };
    return StatusPill(label: status.label, color: color);
  }
}
