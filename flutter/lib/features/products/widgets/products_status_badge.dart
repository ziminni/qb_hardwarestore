import 'package:client/core/constants/app_colors.dart';
import 'package:client/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';

class ProductsStatusBadge extends StatelessWidget {
  const ProductsStatusBadge({super.key, required this.isActive});

  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return StatusPill(
      label: isActive ? 'Active' : 'Inactive',
      color: isActive ? AppColors.success : AppColors.textSecondary,
    );
  }
}
