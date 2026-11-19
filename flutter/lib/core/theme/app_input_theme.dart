import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_text_styles.dart';
import 'app_palette.dart';

class AppInputTheme {
  static OutlineInputBorder _border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.medium),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static InputDecorationTheme inputDecoration([AppPalette? palette]) {
    final p = palette ?? AppPalette.classic;
    return InputDecorationTheme(
      filled: true,
      fillColor: p.cardBackground,
      hintStyle: AppTextStyles.bodyMedium.copyWith(color: p.disabled),
      labelStyle: AppTextStyles.bodyMedium.copyWith(color: p.textSecondary),
      floatingLabelStyle: AppTextStyles.labelLarge.copyWith(color: p.accentInk),
      prefixIconColor: p.textSecondary,
      suffixIconColor: p.textSecondary,
      border: _border(p.border),
      enabledBorder: _border(p.border),
      focusedBorder: _border(p.accent, 1.6),
      errorBorder: _border(AppColors.error),
      focusedErrorBorder: _border(AppColors.error, 1.6),
      disabledBorder: _border(p.border.withValues(alpha: 0.6)),
    );
  }

  static DropdownMenuThemeData dropdownMenu([AppPalette? palette]) {
    final p = palette ?? AppPalette.classic;
    return DropdownMenuThemeData(
      inputDecorationTheme: inputDecoration(p),
      menuStyle: AppInputTheme.menuStyle(p),
    );
  }

  static MenuStyle menuStyle([AppPalette? palette]) {
    final p = palette ?? AppPalette.classic;
    return MenuStyle(
      backgroundColor: WidgetStatePropertyAll(p.cardBackground),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(6),
      shadowColor: WidgetStatePropertyAll(
        AppColors.brandBlack.withValues(alpha: 0.25),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          side: BorderSide(color: p.border),
        ),
      ),
    );
  }
}
