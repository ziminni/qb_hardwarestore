import 'package:flutter/material.dart';

import '../constants/app_text_styles.dart';
import 'app_palette.dart';

/// The app's Material 3 text scale in the two brand faces.
///
/// One rule covers every slot, the same one the h1 to h4 and body styles
/// already followed: 18 px and larger is Cinzel (a heading), 16 px and smaller
/// is Open Sans (content). Sizes are Material 3's defaults, so a slot the app
/// never styled before does not also change size.
///
/// Every slot must name a family: a slot left out falls back to the platform
/// font (Roboto) for all of its call sites at once.
class AppTextTheme {
  static TextTheme light() => fromPalette(AppPalette.classic);

  static TextTheme fromPalette(AppPalette p) {
    return TextTheme(
      displayLarge: AppTextStyles.h1.copyWith(color: p.textPrimary),
      displayMedium: AppTextStyles.h2.copyWith(color: p.textPrimary),
      displaySmall: AppTextStyles.h3.copyWith(color: p.textPrimary),
      headlineLarge: _heading(28, p.textPrimary),
      headlineMedium: AppTextStyles.h4.copyWith(color: p.textPrimary),
      headlineSmall: _heading(24, p.textPrimary),
      titleLarge: _heading(22, p.textPrimary),
      titleMedium: _content(16, p.textPrimary),
      titleSmall: _content(14, p.textPrimary),
      bodyLarge: AppTextStyles.bodyLarge.copyWith(color: p.textPrimary),
      bodyMedium: AppTextStyles.bodyMedium.copyWith(color: p.textPrimary),
      bodySmall: AppTextStyles.bodySmall.copyWith(color: p.textSecondary),
      labelLarge: AppTextStyles.labelLarge.copyWith(color: p.textPrimary),
      labelMedium: AppTextStyles.labelMedium.copyWith(color: p.textPrimary),
      labelSmall: AppTextStyles.labelSmall.copyWith(color: p.textSecondary),
    );
  }

  static TextStyle _heading(double size, Color color) => TextStyle(
    fontFamily: AppTextStyles.cinzelFont,
    fontSize: size,
    fontWeight: FontWeight.w600,
    color: color,
    height: 1.3,
  );

  static TextStyle _content(double size, Color color) => TextStyle(
    fontFamily: AppTextStyles.outfitFont,
    fontSize: size,
    fontWeight: FontWeight.w600,
    color: color,
    height: 1.4,
  );
}
