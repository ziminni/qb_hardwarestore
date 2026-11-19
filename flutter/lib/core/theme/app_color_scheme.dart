import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'app_palette.dart';

class AppColorScheme {
  static ColorScheme light() => fromPalette(AppPalette.classic);

  static ColorScheme fromPalette(AppPalette p) {
    return ColorScheme.fromSeed(
      seedColor: p.accent,
      brightness: p.brightness,
    ).copyWith(
      primary: p.accent,
      onPrimary: p.onAccent,
      primaryContainer: p.isDark ? p.selected : p.accentLight,
      onPrimaryContainer: p.isDark ? p.accentLight : AppColors.brandBlack,
      secondary: p.isDark ? p.accentLight : AppColors.brandBlack,
      onSecondary: p.isDark ? AppColors.brandBlack : AppColors.brandWhite,
      secondaryContainer: p.selected,
      onSecondaryContainer: p.textPrimary,
      surface: p.cardBackground,
      onSurface: p.textPrimary,
      onSurfaceVariant: p.textSecondary,
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.surfaceSunken,
      surfaceContainer: p.surfaceSunken,
      surfaceContainerHigh: p.surfaceMuted,
      surfaceContainerHighest: p.surfaceMuted,
      outline: p.border,
      outlineVariant: p.border,
      error: AppColors.error,
      onError: AppColors.brandWhite,
      inverseSurface: p.isDark ? AppColors.softWhite : AppColors.brandBlack,
      onInverseSurface: p.isDark ? AppColors.brandBlack : p.accentLight,
    );
  }

  static ColorScheme dark() => fromPalette(
    AppPalette.fromSettings(
      const ThemeSettings(appearance: AppAppearanceMode.obsidianDark),
    ),
  );
}
