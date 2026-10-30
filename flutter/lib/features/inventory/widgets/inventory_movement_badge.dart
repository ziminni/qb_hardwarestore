import 'package:client/core/constants/app_colors.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/shared/widgets/status_pill.dart';
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
    return StatusPill(label: type.label, color: color);
  }
}
