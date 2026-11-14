import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/data/models/sales.dart';
import 'package:flutter/material.dart';

class InventorySalesStatusBadge extends StatelessWidget {
  const InventorySalesStatusBadge({
    super.key,
    required this.label,
    required this.color,
  });
  final String label;
  final Color color;
  factory InventorySalesStatusBadge.sale({
    Key? key,
    required InventorySaleStatus status,
  }) => InventorySalesStatusBadge(
    key: key,
    label: status.label,
    color: switch (status) {
      InventorySaleStatus.completed => AppColors.success,
      InventorySaleStatus.voided => AppColors.error,
      InventorySaleStatus.refunded => AppColors.warning,
    },
  );
  factory InventorySalesStatusBadge.returnStatus({
    Key? key,
    required InventoryReturnStatus status,
  }) => InventorySalesStatusBadge(
    key: key,
    label: status.label,
    color: switch (status) {
      InventoryReturnStatus.completed ||
      InventoryReturnStatus.approved => AppColors.success,
      InventoryReturnStatus.rejected => AppColors.error,
      InventoryReturnStatus.pending => AppColors.warning,
    },
  );
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(AppRadii.pill),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
    ),
  );
}
