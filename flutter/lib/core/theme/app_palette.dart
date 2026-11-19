import 'package:client/core/constants/app_colors.dart';
import 'package:flutter/material.dart';

/// Surface brightness & canvas tone stored locally on this device.
enum AppAppearanceMode {
  warmCream(
    id: 'warm_cream',
    label: 'Warm Cream',
    description: 'Signature Queen Builders parchment workspace',
  ),
  crispDaylight(
    id: 'crisp_daylight',
    label: 'Crisp Daylight',
    description: 'High-contrast bright canvas for sunny counters',
  ),
  obsidianDark(
    id: 'obsidian_dark',
    label: 'Obsidian Dark',
    description: 'Low-glare dark workspace for dim rooms and night shifts',
  );

  const AppAppearanceMode({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;

  bool get isDark => this == AppAppearanceMode.obsidianDark;

  static AppAppearanceMode fromId(String? id) {
    for (final mode in values) {
      if (mode.id == id) return mode;
    }
    return AppAppearanceMode.warmCream;
  }
}

/// Accent colour preset stored locally on this device.
enum AppAccentPreset {
  queenBrass(
    id: 'queen_brass',
    label: 'Queen Brass',
    accent: AppColors.brandGold,
    accentLight: AppColors.brandGoldLight,
    accentInkLight: AppColors.brandGoldText,
    accentInkDark: AppColors.brandGoldLight,
    onAccent: AppColors.brandBlack,
    selectedLight: AppColors.selected,
    selectedDark: Color(0xFF2B2518),
  ),
  royalAmber(
    id: 'royal_amber',
    label: 'Copper Amber',
    accent: Color(0xFFC47D2C),
    accentLight: Color(0xFFF0BC78),
    accentInkLight: Color(0xFF844D12),
    accentInkDark: Color(0xFFF0BC78),
    onAccent: AppColors.brandBlack,
    selectedLight: Color(0xFFF7E6CF),
    selectedDark: Color(0xFF2D2115),
  ),
  blueprintCobalt(
    id: 'blueprint_cobalt',
    label: 'Blueprint Blue',
    accent: Color(0xFF2D6691),
    accentLight: Color(0xFF8AB8DB),
    accentInkLight: Color(0xFF1F4B6E),
    accentInkDark: Color(0xFF9AC5E6),
    onAccent: AppColors.brandWhite,
    selectedLight: Color(0xFFDBEAF6),
    selectedDark: Color(0xFF172533),
  ),
  workshopEmerald(
    id: 'workshop_emerald',
    label: 'Workshop Green',
    accent: Color(0xFF29785A),
    accentLight: Color(0xFF7BCAA9),
    accentInkLight: Color(0xFF1A543E),
    accentInkDark: Color(0xFF85D1B1),
    onAccent: AppColors.brandWhite,
    selectedLight: Color(0xFFD9F1E6),
    selectedDark: Color(0xFF152922),
  ),
  crimsonForge(
    id: 'crimson_forge',
    label: 'Crimson Forge',
    accent: Color(0xFFA63D3D),
    accentLight: Color(0xFFE59797),
    accentInkLight: Color(0xFF7A2424),
    accentInkDark: Color(0xFFEB9F9F),
    onAccent: AppColors.brandWhite,
    selectedLight: Color(0xFFF5DFDF),
    selectedDark: Color(0xFF2E1919),
  );

  const AppAccentPreset({
    required this.id,
    required this.label,
    required this.accent,
    required this.accentLight,
    required this.accentInkLight,
    required this.accentInkDark,
    required this.onAccent,
    required this.selectedLight,
    required this.selectedDark,
  });

  final String id;
  final String label;
  final Color accent;
  final Color accentLight;
  final Color accentInkLight;
  final Color accentInkDark;
  final Color onAccent;
  final Color selectedLight;
  final Color selectedDark;

  static AppAccentPreset fromId(String? id) {
    for (final preset in values) {
      if (preset.id == id) return preset;
    }
    return AppAccentPreset.queenBrass;
  }
}

/// Sidebar chrome appearance stored locally on this device.
enum AppSidebarStyle {
  obsidian(
    id: 'obsidian',
    label: 'Obsidian Chrome',
    description: 'Signature deep-black navigation rail',
  ),
  charcoal(
    id: 'charcoal',
    label: 'Graphite Slate',
    description: 'Softer dark charcoal navigation rail',
  ),
  light(
    id: 'light',
    label: 'Matching Light',
    description: 'Bright navigation surface on light workspaces',
  );

  const AppSidebarStyle({
    required this.id,
    required this.label,
    required this.description,
  });

  final String id;
  final String label;
  final String description;

  static AppSidebarStyle fromId(String? id) {
    for (final style in values) {
      if (style.id == id) return style;
    }
    return AppSidebarStyle.obsidian;
  }
}

/// Interface text-size comfort preference stored locally on this device.
enum AppDisplayScale {
  compact(id: 'compact', label: 'Compact', factor: 0.94),
  standard(id: 'standard', label: 'Standard', factor: 1.0),
  comfortable(id: 'comfortable', label: 'Comfortable', factor: 1.08);

  const AppDisplayScale({
    required this.id,
    required this.label,
    required this.factor,
  });

  final String id;
  final String label;
  final double factor;

  static AppDisplayScale fromId(String? id) {
    for (final scale in values) {
      if (scale.id == id) return scale;
    }
    return AppDisplayScale.standard;
  }
}

/// Immutable bundle of local-device visual preferences.
@immutable
class ThemeSettings {
  const ThemeSettings({
    this.appearance = AppAppearanceMode.warmCream,
    this.accent = AppAccentPreset.queenBrass,
    this.sidebarStyle = AppSidebarStyle.obsidian,
    this.displayScale = AppDisplayScale.standard,
  });

  static const ThemeSettings defaults = ThemeSettings();

  final AppAppearanceMode appearance;
  final AppAccentPreset accent;
  final AppSidebarStyle sidebarStyle;
  final AppDisplayScale displayScale;

  bool get isDefault => this == defaults;

  ThemeSettings copyWith({
    AppAppearanceMode? appearance,
    AppAccentPreset? accent,
    AppSidebarStyle? sidebarStyle,
    AppDisplayScale? displayScale,
  }) {
    return ThemeSettings(
      appearance: appearance ?? this.appearance,
      accent: accent ?? this.accent,
      sidebarStyle: sidebarStyle ?? this.sidebarStyle,
      displayScale: displayScale ?? this.displayScale,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ThemeSettings &&
        other.appearance == appearance &&
        other.accent == accent &&
        other.sidebarStyle == sidebarStyle &&
        other.displayScale == displayScale;
  }

  @override
  int get hashCode =>
      Object.hash(appearance, accent, sidebarStyle, displayScale);
}

/// Resolved semantic colours exposed via [ThemeData.extension] so every shell,
/// panel, sidebar, and form reacts cleanly to local-device theme changes while
/// defaulting to the exact Queen Builders palette.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.brightness,
    required this.background,
    required this.cardBackground,
    required this.surfaceSunken,
    required this.surfaceMuted,
    required this.tableHeader,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.disabled,
    required this.accent,
    required this.accentLight,
    required this.accentInk,
    required this.onAccent,
    required this.selected,
    required this.sidebarBg,
    required this.sidebarRaised,
    required this.sidebarBorder,
    required this.sidebarText,
    required this.sidebarHoverText,
    required this.sidebarActiveText,
    required this.sidebarSubtitle,
    required this.sidebarIsLight,
  });

  final Brightness brightness;
  final Color background;
  final Color cardBackground;
  final Color surfaceSunken;
  final Color surfaceMuted;
  final Color tableHeader;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color disabled;
  final Color accent;
  final Color accentLight;
  final Color accentInk;
  final Color onAccent;
  final Color selected;

  // Sidebar chrome tokens (adapt independently for obsidian / slate / light).
  final Color sidebarBg;
  final Color sidebarRaised;
  final Color sidebarBorder;
  final Color sidebarText;
  final Color sidebarHoverText;
  final Color sidebarActiveText;
  final Color sidebarSubtitle;
  final bool sidebarIsLight;

  bool get isDark => brightness == Brightness.dark;

  /// Queen Builders' classic default palette — exact values of [AppColors].
  static final AppPalette classic = AppPalette.fromSettings(
    ThemeSettings.defaults,
  );

  /// Safe lookup that returns [classic] if a test pumps a widget without
  /// [AppTheme.lightTheme].
  static AppPalette of(BuildContext context) {
    return Theme.of(context).extension<AppPalette>() ?? classic;
  }

  factory AppPalette.fromSettings(ThemeSettings settings) {
    final accentPreset = settings.accent;
    final dark = settings.appearance.isDark;

    final Color background;
    final Color cardBackground;
    final Color surfaceSunken;
    final Color surfaceMuted;
    final Color tableHeader;
    final Color border;
    final Color textPrimary;
    final Color textSecondary;
    final Color disabled;

    switch (settings.appearance) {
      case AppAppearanceMode.warmCream:
        background = AppColors.background;
        cardBackground = AppColors.cardBackground;
        surfaceSunken = AppColors.surfaceSunken;
        surfaceMuted = AppColors.surfaceMuted;
        tableHeader = AppColors.tableHeader;
        border = AppColors.border;
        textPrimary = AppColors.textPrimary;
        textSecondary = AppColors.textSecondary;
        disabled = AppColors.disabled;
      case AppAppearanceMode.crispDaylight:
        background = const Color(0xFFF3F5F8);
        cardBackground = const Color(0xFFFFFFFF);
        surfaceSunken = const Color(0xFFEAEEF4);
        surfaceMuted = const Color(0xFFE1E7F0);
        tableHeader = const Color(0xFFF0F3F8);
        border = const Color(0xFFD0D7E2);
        textPrimary = const Color(0xFF0E141B);
        textSecondary = const Color(0xFF535E6E);
        disabled = const Color(0xFF939DAC);
      case AppAppearanceMode.obsidianDark:
        background = const Color(0xFF111110);
        cardBackground = const Color(0xFF1A1917);
        surfaceSunken = const Color(0xFF23211E);
        surfaceMuted = const Color(0xFF2B2824);
        tableHeader = const Color(0xFF211F1C);
        border = const Color(0xFF33302A);
        textPrimary = const Color(0xFFF4F1EA);
        textSecondary = const Color(0xFFA8A194);
        disabled = const Color(0xFF6B665C);
    }

    final accentInk = dark
        ? accentPreset.accentInkDark
        : accentPreset.accentInkLight;
    final selected = dark
        ? accentPreset.selectedDark
        : accentPreset.selectedLight;

    // Matching Light falls back to Graphite Slate when the workspace itself is
    // Obsidian Dark, so the sidebar never blinds a dark-mode user.
    final effectiveSidebar =
        dark && settings.sidebarStyle == AppSidebarStyle.light
        ? AppSidebarStyle.charcoal
        : settings.sidebarStyle;

    final Color sidebarBg;
    final Color sidebarRaised;
    final Color sidebarBorder;
    final Color sidebarText;
    final Color sidebarHoverText;
    final Color sidebarActiveText;
    final Color sidebarSubtitle;
    final bool sidebarIsLight;

    switch (effectiveSidebar) {
      case AppSidebarStyle.obsidian:
        sidebarBg = AppColors.chrome;
        sidebarRaised = AppColors.chromeRaised;
        sidebarBorder = AppColors.chromeBorder;
        sidebarText = AppColors.chromeText;
        sidebarHoverText = AppColors.brandWhite;
        sidebarActiveText = accentPreset.accentLight;
        sidebarSubtitle = accentPreset.accentLight;
        sidebarIsLight = false;
      case AppSidebarStyle.charcoal:
        sidebarBg = const Color(0xFF16181D);
        sidebarRaised = const Color(0xFF20232A);
        sidebarBorder = const Color(0xFF2E323C);
        sidebarText = const Color(0xFFB7BDC9);
        sidebarHoverText = AppColors.brandWhite;
        sidebarActiveText = accentPreset.accentLight;
        sidebarSubtitle = accentPreset.accentLight;
        sidebarIsLight = false;
      case AppSidebarStyle.light:
        sidebarBg = cardBackground;
        sidebarRaised = surfaceSunken;
        sidebarBorder = border;
        sidebarText = textSecondary;
        sidebarHoverText = textPrimary;
        sidebarActiveText = accentInk;
        sidebarSubtitle = accentInk;
        sidebarIsLight = true;
    }

    return AppPalette(
      brightness: dark ? Brightness.dark : Brightness.light,
      background: background,
      cardBackground: cardBackground,
      surfaceSunken: surfaceSunken,
      surfaceMuted: surfaceMuted,
      tableHeader: tableHeader,
      border: border,
      textPrimary: textPrimary,
      textSecondary: textSecondary,
      disabled: disabled,
      accent: accentPreset.accent,
      accentLight: accentPreset.accentLight,
      accentInk: accentInk,
      onAccent: accentPreset.onAccent,
      selected: selected,
      sidebarBg: sidebarBg,
      sidebarRaised: sidebarRaised,
      sidebarBorder: sidebarBorder,
      sidebarText: sidebarText,
      sidebarHoverText: sidebarHoverText,
      sidebarActiveText: sidebarActiveText,
      sidebarSubtitle: sidebarSubtitle,
      sidebarIsLight: sidebarIsLight,
    );
  }

  @override
  AppPalette copyWith({
    Brightness? brightness,
    Color? background,
    Color? cardBackground,
    Color? surfaceSunken,
    Color? surfaceMuted,
    Color? tableHeader,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? disabled,
    Color? accent,
    Color? accentLight,
    Color? accentInk,
    Color? onAccent,
    Color? selected,
    Color? sidebarBg,
    Color? sidebarRaised,
    Color? sidebarBorder,
    Color? sidebarText,
    Color? sidebarHoverText,
    Color? sidebarActiveText,
    Color? sidebarSubtitle,
    bool? sidebarIsLight,
  }) {
    return AppPalette(
      brightness: brightness ?? this.brightness,
      background: background ?? this.background,
      cardBackground: cardBackground ?? this.cardBackground,
      surfaceSunken: surfaceSunken ?? this.surfaceSunken,
      surfaceMuted: surfaceMuted ?? this.surfaceMuted,
      tableHeader: tableHeader ?? this.tableHeader,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      disabled: disabled ?? this.disabled,
      accent: accent ?? this.accent,
      accentLight: accentLight ?? this.accentLight,
      accentInk: accentInk ?? this.accentInk,
      onAccent: onAccent ?? this.onAccent,
      selected: selected ?? this.selected,
      sidebarBg: sidebarBg ?? this.sidebarBg,
      sidebarRaised: sidebarRaised ?? this.sidebarRaised,
      sidebarBorder: sidebarBorder ?? this.sidebarBorder,
      sidebarText: sidebarText ?? this.sidebarText,
      sidebarHoverText: sidebarHoverText ?? this.sidebarHoverText,
      sidebarActiveText: sidebarActiveText ?? this.sidebarActiveText,
      sidebarSubtitle: sidebarSubtitle ?? this.sidebarSubtitle,
      sidebarIsLight: sidebarIsLight ?? this.sidebarIsLight,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      brightness: t < 0.5 ? brightness : other.brightness,
      background: Color.lerp(background, other.background, t)!,
      cardBackground: Color.lerp(cardBackground, other.cardBackground, t)!,
      surfaceSunken: Color.lerp(surfaceSunken, other.surfaceSunken, t)!,
      surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
      tableHeader: Color.lerp(tableHeader, other.tableHeader, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      disabled: Color.lerp(disabled, other.disabled, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentLight: Color.lerp(accentLight, other.accentLight, t)!,
      accentInk: Color.lerp(accentInk, other.accentInk, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      selected: Color.lerp(selected, other.selected, t)!,
      sidebarBg: Color.lerp(sidebarBg, other.sidebarBg, t)!,
      sidebarRaised: Color.lerp(sidebarRaised, other.sidebarRaised, t)!,
      sidebarBorder: Color.lerp(sidebarBorder, other.sidebarBorder, t)!,
      sidebarText: Color.lerp(sidebarText, other.sidebarText, t)!,
      sidebarHoverText: Color.lerp(
        sidebarHoverText,
        other.sidebarHoverText,
        t,
      )!,
      sidebarActiveText: Color.lerp(
        sidebarActiveText,
        other.sidebarActiveText,
        t,
      )!,
      sidebarSubtitle: Color.lerp(sidebarSubtitle, other.sidebarSubtitle, t)!,
      sidebarIsLight: t < 0.5 ? sidebarIsLight : other.sidebarIsLight,
    );
  }
}
