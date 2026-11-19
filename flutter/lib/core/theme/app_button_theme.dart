import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_text_styles.dart';
import 'app_palette.dart';

class AppButtonTheme {
  static final _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadii.medium),
  );

  static const _padding = EdgeInsets.symmetric(horizontal: 18, vertical: 12);

  // Keyboard focus on accent buttons needs a crisp high-contrast ring.
  static WidgetStateProperty<BorderSide?> _focusSideFor(AppPalette p) {
    final ring = p.isDark ? p.accentLight : AppColors.brandBlack;
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return null;
      }
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: ring, width: 2);
      }
      return null;
    });
  }

  static ElevatedButtonThemeData elevatedButton([AppPalette? palette]) {
    final p = palette ?? AppPalette.classic;
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        elevation: 0,
        padding: _padding,
        textStyle: AppTextStyles.button.copyWith(color: p.onAccent),
        shape: _shape,
      ).copyWith(side: _focusSideFor(p)),
    );
  }

  static TextButtonThemeData textButton([AppPalette? palette]) {
    final p = palette ?? AppPalette.classic;
    // `AppTextStyles.button` names the body family. Keeping a family on any
    // textStyle set here prevents falling back to the platform font.
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.textPrimary,
        textStyle: AppTextStyles.button.copyWith(color: p.textPrimary),
        shape: _shape,
      ).copyWith(side: _focusSideFor(p)),
    );
  }

  static FilledButtonThemeData filledButton([AppPalette? palette]) {
    final p = palette ?? AppPalette.classic;
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
        disabledBackgroundColor: p.surfaceMuted,
        disabledForegroundColor: p.disabled,
        padding: _padding,
        textStyle: AppTextStyles.button.copyWith(color: p.onAccent),
        shape: _shape,
      ).copyWith(side: _focusSideFor(p)),
    );
  }

  static OutlinedButtonThemeData outlinedButton([AppPalette? palette]) {
    final p = palette ?? AppPalette.classic;
    return OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            foregroundColor: p.textPrimary,
            backgroundColor: p.cardBackground,
            side: BorderSide(color: p.border),
            padding: _padding,
            textStyle: AppTextStyles.button.copyWith(color: p.textPrimary),
            shape: _shape,
          ).copyWith(
            side: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return BorderSide(color: p.border);
              }
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return BorderSide(color: p.accent);
              }
              return BorderSide(color: p.border);
            }),
          ),
    );
  }

  static IconButtonThemeData iconButton([AppPalette? palette]) {
    final p = palette ?? AppPalette.classic;
    return IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: p.textSecondary,
        hoverColor: p.selected,
        highlightColor: p.selected,
      ),
    );
  }
}
