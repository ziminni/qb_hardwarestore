import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class AppColorScheme {
  static ColorScheme light() {
    return ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
    );
  }

  static ColorScheme dark() {
    return ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
    );
  }
}
