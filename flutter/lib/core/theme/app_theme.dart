import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../constants/app_radii.dart';
import '../constants/app_text_styles.dart';
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
    canvasColor: AppColors.cardBackground,
    splashFactory: InkSparkle.splashFactory,
    hoverColor: AppColors.selected.withValues(alpha: 0.5),
    textTheme: AppTextTheme.light(),
    elevatedButtonTheme: AppButtonTheme.elevatedButton(),
    filledButtonTheme: AppButtonTheme.filledButton(),
    outlinedButtonTheme: AppButtonTheme.outlinedButton(),
    textButtonTheme: AppButtonTheme.textButton(),
    iconButtonTheme: AppButtonTheme.iconButton(),
    inputDecorationTheme: AppInputTheme.inputDecoration(),
    dropdownMenuTheme: AppInputTheme.dropdownMenu(),
    menuTheme: MenuThemeData(style: AppInputTheme.menuStyle()),
    cardTheme: AppCardTheme.card(),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.brandBlack,
      foregroundColor: AppColors.brandGoldLight,
      centerTitle: true,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.cardBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: AppColors.brandBlack.withValues(alpha: 0.4),
      barrierColor: AppColors.brandBlack.withValues(alpha: 0.55),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.large),
        side: const BorderSide(color: AppColors.border),
      ),
      titleTextStyle: AppTextStyles.h3,
      contentTextStyle: AppTextStyles.bodyMedium,
    ),
    dataTableTheme: DataTableThemeData(
      headingRowColor: const WidgetStatePropertyAll(AppColors.tableHeader),
      headingTextStyle: AppTextStyles.labelMedium.copyWith(
        color: AppColors.textSecondary,
        letterSpacing: 0.6,
      ),
      dataTextStyle: AppTextStyles.bodyMedium,
      dataRowColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return AppColors.selected;
        if (states.contains(WidgetState.hovered)) {
          return AppColors.selected.withValues(alpha: 0.45);
        }
        return null;
      }),
      dividerThickness: 1,
      headingRowHeight: 48,
      horizontalMargin: 20,
      columnSpacing: 32,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.surfaceSunken,
      selectedColor: AppColors.brandBlack,
      secondarySelectedColor: AppColors.brandBlack,
      disabledColor: AppColors.surfaceMuted,
      checkmarkColor: AppColors.brandGoldLight,
      side: const BorderSide(color: AppColors.border),
      labelStyle: AppTextStyles.labelMedium,
      secondaryLabelStyle: AppTextStyles.labelMedium.copyWith(
        color: AppColors.brandGoldLight,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: AppColors.brandBlack,
      unselectedLabelColor: AppColors.textSecondary,
      labelStyle: AppTextStyles.labelLarge,
      unselectedLabelStyle: AppTextStyles.labelLarge.copyWith(
        fontWeight: FontWeight.w500,
      ),
      indicatorColor: AppColors.brandGold,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: AppColors.border,
      overlayColor: WidgetStatePropertyAll(
        AppColors.selected.withValues(alpha: 0.5),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        backgroundColor: AppColors.cardBackground,
        foregroundColor: AppColors.textSecondary,
        selectedBackgroundColor: AppColors.brandBlack,
        selectedForegroundColor: AppColors.brandGoldLight,
        side: const BorderSide(color: AppColors.border),
        textStyle: AppTextStyles.labelMedium,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.cardBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      textStyle: AppTextStyles.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textSecondary,
      selectedColor: AppColors.brandBlack,
      selectedTileColor: AppColors.selected,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.brandBlack,
      contentTextStyle: AppTextStyles.bodyMedium.copyWith(
        color: AppColors.brandWhite,
      ),
      actionTextColor: AppColors.brandGoldLight,
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
      ),
      textStyle: AppTextStyles.labelSmall.copyWith(
        color: AppColors.brandGoldLight,
      ),
      waitDuration: const Duration(milliseconds: 400),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.brandGold,
      linearTrackColor: AppColors.surfaceMuted,
      circularTrackColor: Colors.transparent,
    ),
    badgeTheme: const BadgeThemeData(
      backgroundColor: AppColors.brandGold,
      textColor: AppColors.brandBlack,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.brandGoldLight
            : AppColors.disabled;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.brandBlack
            : AppColors.surfaceMuted;
      }),
      trackOutlineColor: const WidgetStatePropertyAll(AppColors.border),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith((states) {
        return states.contains(WidgetState.selected)
            ? AppColors.brandGold
            : AppColors.textSecondary;
      }),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(
        AppColors.brandGold.withValues(alpha: 0.45),
      ),
      radius: const Radius.circular(AppRadii.pill),
      thickness: const WidgetStatePropertyAll(6),
    ),
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
