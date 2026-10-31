import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class AppColorScheme {
  static ColorScheme light() {
    return ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.brandGold,
      onPrimary: AppColors.brandBlack,
      primaryContainer: AppColors.brandGoldLight,
      onPrimaryContainer: AppColors.brandBlack,
      secondary: AppColors.brandBlack,
      onSecondary: AppColors.brandWhite,
      secondaryContainer: AppColors.selected,
      onSecondaryContainer: AppColors.brandBlack,
      surface: AppColors.cardBackground,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.background,
      surfaceContainerLow: AppColors.surfaceSunken,
      surfaceContainer: AppColors.surfaceSunken,
      surfaceContainerHigh: AppColors.surfaceMuted,
      surfaceContainerHighest: AppColors.surfaceMuted,
      outline: AppColors.border,
      outlineVariant: AppColors.border,
      error: AppColors.error,
      onError: AppColors.brandWhite,
      inverseSurface: AppColors.brandBlack,
      onInverseSurface: AppColors.brandGoldLight,
    );
  }

  static ColorScheme dark() {
    return ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: AppColors.brandGoldLight,
      onPrimary: AppColors.brandBlack,
      primaryContainer: AppColors.brandGold,
      onPrimaryContainer: AppColors.brandBlack,
      secondary: AppColors.brandGold,
      onSecondary: AppColors.brandBlack,
      surface: const Color(0xFF171717),
      onSurface: AppColors.brandWhite,
      outline: const Color(0xFF756A50),
      error: AppColors.error,
      onError: AppColors.brandWhite,
    );
  }
}
