import 'package:flutter/material.dart';

import '../constants/app_radii.dart';
import '../constants/app_spacing.dart';
import 'app_palette.dart';

class AppCardTheme {
  static CardThemeData card([AppPalette? palette]) {
    final p = palette ?? AppPalette.classic;
    return CardThemeData(
      color: p.cardBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.all(AppSpacing.md),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: p.border),
        borderRadius: BorderRadius.circular(AppRadii.medium),
      ),
    );
  }
}
