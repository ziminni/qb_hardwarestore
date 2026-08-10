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
    textButtonTheme: AppButtonTheme.textButton(),
    inputDecorationTheme: AppInputTheme.inputDecoration(),
    cardTheme: AppCardTheme.card(),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.textLight,
      centerTitle: true,
    ),
  );
}
