import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/data/models/inventory.dart';
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
