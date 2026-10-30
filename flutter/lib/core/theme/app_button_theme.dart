import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_radii.dart';

class AppButtonTheme {
  static ElevatedButtonThemeData elevatedButton() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.brandBlack,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
      ),
    );
  }

  static TextButtonThemeData textButton() {
    // No textStyle here: a partial TextStyle replaces the labelLarge the other
    // two button styles inherit from, which dropped every TextButton label to
    // the platform font. Letting the theme supply it keeps the brand family.
    return TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.brandBlack),
    );
  }

  static FilledButtonThemeData filledButton() {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.brandBlack,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
      ),
    );
  }

  static OutlinedButtonThemeData outlinedButton() {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.brandBlack,
        side: const BorderSide(color: AppColors.brandGold),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
      ),
    );
  }
}
