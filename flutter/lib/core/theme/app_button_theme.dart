import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_text_styles.dart';

class AppButtonTheme {
  static final _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadii.medium),
  );

  static const _padding = EdgeInsets.symmetric(horizontal: 18, vertical: 12);

  static ElevatedButtonThemeData elevatedButton() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.brandBlack,
        elevation: 0,
        padding: _padding,
        textStyle: AppTextStyles.button,
        shape: _shape,
      ),
    );
  }

  static TextButtonThemeData textButton() {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.brandBlack,
        textStyle: AppTextStyles.button,
        shape: _shape,
      ),
    );
  }

  static FilledButtonThemeData filledButton() {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.brandBlack,
        disabledBackgroundColor: AppColors.surfaceMuted,
        disabledForegroundColor: AppColors.disabled,
        padding: _padding,
        textStyle: AppTextStyles.button,
        shape: _shape,
      ),
    );
  }

  static OutlinedButtonThemeData outlinedButton() {
    return OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            foregroundColor: AppColors.brandBlack,
            backgroundColor: AppColors.cardBackground,
            side: const BorderSide(color: AppColors.border),
            padding: _padding,
            textStyle: AppTextStyles.button,
            shape: _shape,
          ).copyWith(
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return const BorderSide(color: AppColors.border);
              }
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return const BorderSide(color: AppColors.brandGold);
              }
              return const BorderSide(color: AppColors.border);
            }),
          ),
    );
  }

  static IconButtonThemeData iconButton() {
    return IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.textSecondary,
        hoverColor: AppColors.selected,
        highlightColor: AppColors.selected,
      ),
    );
  }
}
