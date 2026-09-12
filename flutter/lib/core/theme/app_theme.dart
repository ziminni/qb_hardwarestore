import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'app_button_theme.dart';
import 'app_card_theme.dart';
import 'app_color_scheme.dart';
import 'app_input_theme.dart';
import 'app_text_theme.dart';

class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    colorScheme: AppColorScheme.light(),
    scaffoldBackgroundColor: AppColors.background,
    textTheme: AppTextTheme.light(),
    elevatedButtonTheme: AppButtonTheme.elevatedButton(),
    filledButtonTheme: AppButtonTheme.filledButton(),
    outlinedButtonTheme: AppButtonTheme.outlinedButton(),
    textButtonTheme: AppButtonTheme.textButton(),
    inputDecorationTheme: AppInputTheme.inputDecoration(),
    cardTheme: AppCardTheme.card(),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.brandBlack,
      foregroundColor: AppColors.brandGoldLight,
      centerTitle: true,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.brandGold
            : AppColors.cardBackground;
      }),
      checkColor: const WidgetStatePropertyAll(AppColors.brandBlack),
      side: const BorderSide(color: AppColors.brandGold),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.brandGold,
      foregroundColor: AppColors.brandBlack,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: AppColors.brandGold,
      selectionColor: AppColors.brandGoldLight,
      selectionHandleColor: AppColors.brandGold,
    ),
  );
}
