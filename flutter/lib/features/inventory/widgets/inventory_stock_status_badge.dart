import 'package:client/core/constants/app_colors.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';

class InventoryStockStatusBadge extends StatelessWidget {
  const InventoryStockStatusBadge({super.key, required this.status});

  final InventoryStockStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      InventoryStockStatus.inStock => AppColors.success,
      InventoryStockStatus.lowStock => AppColors.warning,
      InventoryStockStatus.outOfStock => AppColors.error,
    };
    return StatusPill(label: status.label, color: color);
  }
}
