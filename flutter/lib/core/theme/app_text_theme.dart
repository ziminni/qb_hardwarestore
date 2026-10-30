import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_text_styles.dart';

class AppTextTheme {
  static TextTheme light() {
    return TextTheme(
      displayLarge: AppTextStyles.h1,
      displayMedium: AppTextStyles.h2,
      displaySmall: AppTextStyles.h3,
      // Headlines carry figures (totals, metrics), so they use Open Sans.
      headlineLarge: _figure(30),
      headlineMedium: _figure(24),
      headlineSmall: _figure(22),
      titleLarge: AppTextStyles.bodyLarge.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 1.3,
      ),
      titleMedium: AppTextStyles.bodyMedium.copyWith(
        fontWeight: FontWeight.w500,
      ),
      titleSmall: AppTextStyles.bodyMedium.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: AppTextStyles.bodyLarge,
      bodyMedium: AppTextStyles.bodyMedium,
      bodySmall: AppTextStyles.bodySmall,
      labelLarge: AppTextStyles.labelLarge,
      labelMedium: AppTextStyles.labelMedium,
      labelSmall: AppTextStyles.labelSmall,
    ).apply(displayColor: AppColors.textPrimary);
  }

  static TextStyle _figure(double size) {
    return AppTextStyles.bodyLarge.copyWith(
      fontSize: size,
      fontWeight: FontWeight.w700,
      height: 1.25,
      letterSpacing: -0.2,
    );
  }
}
