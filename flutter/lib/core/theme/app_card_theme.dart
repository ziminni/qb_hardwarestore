import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';

class AppCardTheme {
  static CardThemeData card() {
    return CardThemeData(
      color: AppColors.cardBackground,
      elevation: 2,
      margin: EdgeInsets.all(AppSpacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
    );
  }
}
