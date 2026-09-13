import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/data/models/inventory.dart';
import 'package:flutter/material.dart';

class InventoryMovementBadge extends StatelessWidget {
  const InventoryMovementBadge({super.key, required this.type});
  final InventoryMovementType type;
  @override
  Widget build(BuildContext context) {
    final color = switch (type) {
      InventoryMovementType.initialStock => AppColors.primary,
      InventoryMovementType.purchaseReceipt ||
      InventoryMovementType.customerReturn => AppColors.success,
      InventoryMovementType.sale ||
      InventoryMovementType.supplierReturn => AppColors.error,
      InventoryMovementType.stockAdjustment => AppColors.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        type.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
