import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_text_styles.dart';

class AppInputTheme {
  static OutlineInputBorder _border(Color color, [double width = 1]) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.medium),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  static InputDecorationTheme inputDecoration() {
    return InputDecorationTheme(
      filled: true,
      fillColor: AppColors.cardBackground,
      hintStyle: AppTextStyles.bodyMedium.copyWith(color: AppColors.disabled),
      labelStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.textSecondary,
      ),
      floatingLabelStyle: AppTextStyles.labelLarge.copyWith(
        color: AppColors.brandGold,
      ),
      prefixIconColor: AppColors.textSecondary,
      suffixIconColor: AppColors.textSecondary,
      border: _border(AppColors.border),
      enabledBorder: _border(AppColors.border),
      focusedBorder: _border(AppColors.primary, 1.6),
      errorBorder: _border(AppColors.error),
      focusedErrorBorder: _border(AppColors.error, 1.6),
      disabledBorder: _border(AppColors.border.withValues(alpha: 0.6)),
    );
  }

  static DropdownMenuThemeData dropdownMenu() {
    return DropdownMenuThemeData(
      inputDecorationTheme: inputDecoration(),
      menuStyle: AppInputTheme.menuStyle(),
    );
  }

  static MenuStyle menuStyle() {
    return MenuStyle(
      backgroundColor: const WidgetStatePropertyAll(AppColors.cardBackground),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      elevation: const WidgetStatePropertyAll(6),
      shadowColor: WidgetStatePropertyAll(
        AppColors.brandBlack.withValues(alpha: 0.25),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}
