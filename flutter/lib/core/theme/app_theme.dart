import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_text_styles.dart';
import 'app_button_theme.dart';
import 'app_card_theme.dart';
import 'app_color_scheme.dart';
import 'app_input_theme.dart';
import 'app_palette.dart';
import 'app_text_theme.dart';

class AppTheme {
  static final ThemeData lightTheme = buildTheme(ThemeSettings.defaults);

  static ThemeData buildTheme(ThemeSettings settings) {
    final p = AppPalette.fromSettings(settings);
    final selectedBg = p.isDark ? p.accent : AppColors.brandBlack;
    final selectedFg = p.isDark ? p.onAccent : p.accentLight;

    return ThemeData(
      useMaterial3: true,
      brightness: p.brightness,
      colorScheme: AppColorScheme.fromPalette(p),
      extensions: [p],
      scaffoldBackgroundColor: p.background,
      canvasColor: p.cardBackground,
      splashFactory: InkSparkle.splashFactory,
      hoverColor: p.selected.withValues(alpha: 0.5),
      textTheme: AppTextTheme.fromPalette(p),
      elevatedButtonTheme: AppButtonTheme.elevatedButton(p),
      filledButtonTheme: AppButtonTheme.filledButton(p),
      outlinedButtonTheme: AppButtonTheme.outlinedButton(p),
      textButtonTheme: AppButtonTheme.textButton(p),
      iconButtonTheme: AppButtonTheme.iconButton(p),
      inputDecorationTheme: AppInputTheme.inputDecoration(p),
      dropdownMenuTheme: AppInputTheme.dropdownMenu(p),
      menuTheme: MenuThemeData(style: AppInputTheme.menuStyle(p)),
      cardTheme: AppCardTheme.card(p),
      appBarTheme: AppBarTheme(
        backgroundColor: p.sidebarBg,
        foregroundColor: p.sidebarActiveText,
        centerTitle: true,
      ),
      dividerTheme: DividerThemeData(color: p.border, thickness: 1),
      dialogTheme: DialogThemeData(
        backgroundColor: p.cardBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shadowColor: AppColors.brandBlack.withValues(alpha: 0.4),
        barrierColor: AppColors.brandBlack.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.large),
          side: BorderSide(color: p.border),
        ),
        titleTextStyle: AppTextStyles.h3.copyWith(color: p.textPrimary),
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(
          color: p.textPrimary,
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(p.tableHeader),
        headingTextStyle: AppTextStyles.labelMedium.copyWith(
          color: p.textSecondary,
          letterSpacing: 0.6,
        ),
        dataTextStyle: AppTextStyles.bodyMedium.copyWith(color: p.textPrimary),
        dataRowColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return p.selected;
          if (states.contains(WidgetState.hovered)) {
            return p.selected.withValues(alpha: 0.45);
          }
          return null;
        }),
        dividerThickness: 1,
        headingRowHeight: 48,
        horizontalMargin: 20,
        columnSpacing: 32,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: p.surfaceSunken,
        selectedColor: selectedBg,
        secondarySelectedColor: selectedBg,
        disabledColor: p.surfaceMuted,
        checkmarkColor: selectedFg,
        side: BorderSide(color: p.border),
        labelStyle: AppTextStyles.labelMedium.copyWith(color: p.textPrimary),
        secondaryLabelStyle: AppTextStyles.labelMedium.copyWith(
          color: selectedFg,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: p.textPrimary,
        unselectedLabelColor: p.textSecondary,
        labelStyle: AppTextStyles.labelLarge.copyWith(color: p.textPrimary),
        unselectedLabelStyle: AppTextStyles.labelLarge.copyWith(
          fontWeight: FontWeight.w500,
          color: p.textSecondary,
        ),
        indicatorColor: p.accent,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: p.border,
        overlayColor: WidgetStatePropertyAll(p.selected.withValues(alpha: 0.5)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: p.cardBackground,
          foregroundColor: p.textSecondary,
          selectedBackgroundColor: selectedBg,
          selectedForegroundColor: selectedFg,
          side: BorderSide(color: p.border),
          textStyle: AppTextStyles.labelMedium,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: p.cardBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 6,
        textStyle: AppTextStyles.bodyMedium.copyWith(color: p.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
          side: BorderSide(color: p.border),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: p.textSecondary,
        textColor: p.textPrimary,
        selectedColor: p.textPrimary,
        selectedTileColor: p.selected,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.isDark ? p.surfaceMuted : AppColors.brandBlack,
        contentTextStyle: AppTextStyles.bodyMedium.copyWith(
          color: AppColors.brandWhite,
        ),
        actionTextColor: p.accentLight,
        behavior: SnackBarBehavior.floating,
        width: 420,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.medium),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.brandBlack,
          borderRadius: BorderRadius.circular(AppRadii.small),
          border: p.isDark ? Border.all(color: p.border) : null,
        ),
        textStyle: AppTextStyles.labelSmall.copyWith(color: p.accentLight),
        waitDuration: const Duration(milliseconds: 400),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: p.accent,
        linearTrackColor: p.surfaceMuted,
        circularTrackColor: Colors.transparent,
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: p.accent,
        textColor: p.onAccent,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? p.accentLight
              : p.disabled;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? (p.isDark ? p.accent : AppColors.brandBlack)
              : p.surfaceMuted;
        }),
        trackOutlineColor: WidgetStatePropertyAll(p.border),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? p.accent
              : p.textSecondary;
        }),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(p.accent.withValues(alpha: 0.45)),
        radius: const Radius.circular(AppRadii.pill),
        thickness: const WidgetStatePropertyAll(6),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          return states.contains(WidgetState.selected)
              ? p.accent
              : p.cardBackground;
        }),
        checkColor: WidgetStatePropertyAll(p.onAccent),
        side: BorderSide(color: p.accent),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.accent,
        foregroundColor: p.onAccent,
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: p.accent,
        selectionColor: p.accentLight.withValues(alpha: p.isDark ? 0.35 : 0.7),
        selectionHandleColor: p.accent,
      ),
    );
  }
}
