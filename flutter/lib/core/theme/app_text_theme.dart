import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

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
  static TextTheme light() {
    return TextTheme(
      displayLarge: AppTextStyles.h1,
      displayMedium: AppTextStyles.h2,
      displaySmall: AppTextStyles.h3,
      headlineLarge: _heading(28),
      headlineMedium: AppTextStyles.h4,
      headlineSmall: _heading(24),
      titleLarge: _heading(22),
      titleMedium: _content(16),
      titleSmall: _content(14),
      bodyLarge: AppTextStyles.bodyLarge,
      bodyMedium: AppTextStyles.bodyMedium,
      bodySmall: AppTextStyles.bodySmall,
      labelLarge: AppTextStyles.labelLarge,
      labelMedium: AppTextStyles.labelMedium,
      labelSmall: AppTextStyles.labelSmall,
    );
  }

  static TextStyle _heading(double size) => TextStyle(
    fontFamily: AppTextStyles.cinzelFont,
    fontSize: size,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.3,
  );

  static TextStyle _content(double size) => TextStyle(
    fontFamily: AppTextStyles.outfitFont,
    fontSize: size,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
    height: 1.4,
  );
}
