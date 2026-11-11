import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_text_styles.dart';

class AppButtonTheme {
  static final _shape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadii.medium),
  );

  static const _padding = EdgeInsets.symmetric(horizontal: 18, vertical: 12);

  // Keyboard focus on the gold buttons used to be invisible: the only change
  // was the faint state overlay against a gold fill. A black ring reads at a
  // glance and matches the brandBlack foreground.
  static final WidgetStateProperty<BorderSide?> _focusSide =
      WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return null;
        }
        if (states.contains(WidgetState.focused)) {
          return const BorderSide(color: AppColors.brandBlack, width: 2);
        }
        return null;
      });

  static ElevatedButtonThemeData elevatedButton() {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.brandBlack,
        elevation: 0,
        padding: _padding,
        textStyle: AppTextStyles.button,
        shape: _shape,
      ).copyWith(side: _focusSide),
    );
  }

  static TextButtonThemeData textButton() {
    // `AppTextStyles.button` names the body family. A bare `TextStyle` here
    // (fontWeight only, as it once was) replaces the labelLarge the other
    // button styles inherit from and drops every TextButton label to the
    // platform font; keep a family on any textStyle set here.
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.brandBlack,
        textStyle: AppTextStyles.button,
        shape: _shape,
      ).copyWith(side: _focusSide),
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
      ).copyWith(side: _focusSide),
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
