import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/core/theme/theme_settings_controller.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:flutter/material.dart';

/// Local-device appearance and theme customizer embedded inside Settings.
///
/// Every change applies immediately and persists only to this computer/device's
/// `SharedPreferences` — zero backend requests and zero changes to store rules.
class SystemSettingsPanel extends StatelessWidget {
  const SystemSettingsPanel({super.key, this.controller});

  /// Injected by tests; defaults to [ThemeSettingsController.instance].
  final ThemeSettingsController? controller;

  @override
  Widget build(BuildContext context) {
    final ctrl = controller ?? ThemeSettingsController.instance;
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final settings = ctrl.settings;
        final p = AppPalette.of(context);
        final previewPalette = AppPalette.fromSettings(settings);

        return Column(
          key: const ValueKey('system-settings-panel'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DeviceLocalNotice(palette: p),
            const SizedBox(height: AppSpacing.lg),
            AppPanel(
              title: 'Live preview',
              trailing: OutlinedButton.icon(
                key: const ValueKey('theme-reset-button'),
                onPressed: settings.isDefault ? null : ctrl.reset,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  minimumSize: const Size(0, 34),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
                icon: const Icon(Icons.restart_alt_rounded, size: 16),
                label: const Text('Reset default'),
              ),
              child: _ThemeLivePreview(
                settings: settings,
                preview: previewPalette,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPanel(
              title: 'Workspace appearance',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Choose the background and surface contrast for this device.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 560 ? 3 : 1;
                      if (columns == 1) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final mode in AppAppearanceMode.values) ...[
                              _AppearanceOptionCard(
                                mode: mode,
                                accent: settings.accent,
                                selected: settings.appearance == mode,
                                onTap: () => ctrl.setAppearance(mode),
                              ),
                              if (mode != AppAppearanceMode.values.last)
                                const SizedBox(height: AppSpacing.sm),
                            ],
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (i, mode)
                              in AppAppearanceMode.values.indexed) ...[
                            if (i > 0) const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: _AppearanceOptionCard(
                                mode: mode,
                                accent: settings.accent,
                                selected: settings.appearance == mode,
                                onTap: () => ctrl.setAppearance(mode),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPanel(
              title: 'Accent palette',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Customize highlights, active navigation markers, buttons, and focus rings.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final preset in AppAccentPreset.values)
                        _AccentSwatchChip(
                          preset: preset,
                          selected: settings.accent == preset,
                          onTap: () => ctrl.setAccent(preset),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPanel(
              title: 'Navigation sidebar',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Pick the chrome finish for the left navigation bar on this screen.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 560;
                      if (!wide) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final style in AppSidebarStyle.values) ...[
                              _SidebarStyleCard(
                                style: style,
                                settings: settings,
                                selected: settings.sidebarStyle == style,
                                onTap: () => ctrl.setSidebarStyle(style),
                              ),
                              if (style != AppSidebarStyle.values.last)
                                const SizedBox(height: AppSpacing.sm),
                            ],
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final (i, style)
                              in AppSidebarStyle.values.indexed) ...[
                            if (i > 0) const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: _SidebarStyleCard(
                                style: style,
                                settings: settings,
                                selected: settings.sidebarStyle == style,
                                onTap: () => ctrl.setSidebarStyle(style),
                              ),
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                  if (settings.appearance.isDark &&
                      settings.sidebarStyle == AppSidebarStyle.light) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Matching Light automatically uses Graphite Slate while Obsidian Dark mode is active.',
                      style: AppTextStyles.bodySmall.copyWith(
                        color: p.textSecondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            AppPanel(
              title: 'Display comfort',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Adjust interface text sizing for this monitor or till screen.',
                    style: AppTextStyles.bodySmall.copyWith(
                      color: p.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final scale in AppDisplayScale.values)
                        _DisplayScaleChip(
                          scale: scale,
                          selected: settings.displayScale == scale,
                          onTap: () => ctrl.setDisplayScale(scale),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _DeviceLocalNotice extends StatelessWidget {
  const _DeviceLocalNotice({required this.palette});

  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: palette.surfaceSunken,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(Icons.devices_outlined, size: 18, color: palette.accentInk),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Saved on this device only. Customizing your theme updates this '
              'screen immediately without changing store settings or other terminals.',
              style: AppTextStyles.bodySmall.copyWith(
                color: palette.textSecondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeLivePreview extends StatelessWidget {
  const _ThemeLivePreview({required this.settings, required this.preview});

  final ThemeSettings settings;
  final AppPalette preview;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 148,
      decoration: BoxDecoration(
        color: preview.background,
        borderRadius: BorderRadius.circular(AppRadii.medium),
        border: Border.all(color: preview.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Mini sidebar preview
          Container(
            width: 96,
            decoration: BoxDecoration(
              color: preview.sidebarBg,
              border: Border(right: BorderSide(color: preview.sidebarBorder)),
            ),
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: AppColors.brandWhite,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: preview.accent.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: preview.sidebarIsLight
                              ? preview.textPrimary.withValues(alpha: 0.7)
                              : AppColors.brandWhite.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Active nav row
                Container(
                  height: 22,
                  decoration: BoxDecoration(
                    color: preview.sidebarIsLight
                        ? preview.selected
                        : preview.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: preview.accent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 12,
                        margin: const EdgeInsets.only(left: 1),
                        decoration: BoxDecoration(
                          color: preview.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          height: 5,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            color: preview.sidebarActiveText,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < 2; i++) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Container(
                      height: 5,
                      width: i == 0 ? 48 : 38,
                      decoration: BoxDecoration(
                        color: preview.sidebarText.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                Container(
                  height: 20,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: preview.sidebarRaised,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: preview.sidebarBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: preview.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: preview.sidebarText.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Mini header + workspace preview
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [preview.accent, preview.accentLight],
                    ),
                  ),
                ),
                Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: preview.cardBackground,
                    border: Border(bottom: BorderSide(color: preview.border)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 14,
                        decoration: BoxDecoration(
                          color: preview.accent,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${settings.appearance.label} · ${settings.accent.label}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.labelSmall.copyWith(
                            fontFamily: AppTextStyles.cinzelFont,
                            color: preview.textPrimary,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: preview.surfaceSunken,
                          borderRadius: BorderRadius.circular(AppRadii.pill),
                          border: Border.all(color: preview.border),
                        ),
                        child: Text(
                          '${(settings.displayScale.factor * 100).round()}%',
                          style: TextStyle(
                            fontFamily: AppTextStyles.outfitFont,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: preview.accentInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: preview.cardBackground,
                        borderRadius: BorderRadius.circular(AppRadii.small),
                        border: Border.all(color: preview.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Queen Builders Workspace',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.labelLarge.copyWith(
                                    color: preview.textPrimary,
                                    fontSize: 12.5,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Cards, inputs, headers, and accents update live.',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTextStyles.bodySmall.copyWith(
                                    color: preview.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: preview.accent,
                              borderRadius: BorderRadius.circular(
                                AppRadii.small,
                              ),
                            ),
                            child: Text(
                              'Primary',
                              style: TextStyle(
                                fontFamily: AppTextStyles.outfitFont,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: preview.onAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppearanceOptionCard extends StatelessWidget {
  const _AppearanceOptionCard({
    required this.mode,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final AppAppearanceMode mode;
  final AppAccentPreset accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final sample = AppPalette.fromSettings(
      ThemeSettings(appearance: mode, accent: accent),
    );

    return Material(
      key: ValueKey('theme-appearance-${mode.id}'),
      color: selected ? p.selected.withValues(alpha: 0.55) : p.surfaceSunken,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        side: BorderSide(
          color: selected ? p.accent : p.border,
          width: selected ? 1.8 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Miniature surface swatch
              Container(
                height: 44,
                decoration: BoxDecoration(
                  color: sample.background,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                  border: Border.all(color: sample.border),
                ),
                padding: const EdgeInsets.all(6),
                child: Row(
                  children: [
                    Container(
                      width: 16,
                      decoration: BoxDecoration(
                        color: sample.sidebarBg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: sample.cardBackground,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: sample.border),
                        ),
                        padding: const EdgeInsets.all(5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              height: 4,
                              width: 34,
                              decoration: BoxDecoration(
                                color: sample.accent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 5),
                            Container(
                              height: 4,
                              width: 54,
                              decoration: BoxDecoration(
                                color: sample.textSecondary.withValues(
                                  alpha: 0.45,
                                ),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      mode.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.labelLarge.copyWith(
                        fontSize: 13.5,
                        color: p.textPrimary,
                      ),
                    ),
                  ),
                  if (selected)
                    Icon(
                      Icons.check_circle_rounded,
                      size: 17,
                      color: p.accentInk,
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                mode.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.bodySmall.copyWith(
                  fontSize: 11.5,
                  color: p.textSecondary,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccentSwatchChip extends StatelessWidget {
  const _AccentSwatchChip({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final AppAccentPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Material(
      key: ValueKey('theme-accent-${preset.id}'),
      color: selected ? p.selected.withValues(alpha: 0.65) : p.surfaceSunken,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        side: BorderSide(
          color: selected ? preset.accent : p.border,
          width: selected ? 1.8 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 13, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [preset.accentLight, preset.accent],
                  ),
                  border: Border.all(
                    color: p.isDark
                        ? AppColors.brandWhite.withValues(alpha: 0.25)
                        : AppColors.brandBlack.withValues(alpha: 0.15),
                  ),
                ),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: preset.onAccent,
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                preset.label,
                style: AppTextStyles.labelMedium.copyWith(
                  fontSize: 12.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SidebarStyleCard extends StatelessWidget {
  const _SidebarStyleCard({
    required this.style,
    required this.settings,
    required this.selected,
    required this.onTap,
  });

  final AppSidebarStyle style;
  final ThemeSettings settings;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final preview = AppPalette.fromSettings(
      settings.copyWith(sidebarStyle: style),
    );

    return Material(
      key: ValueKey('theme-sidebar-${style.id}'),
      color: selected ? p.selected.withValues(alpha: 0.55) : p.surfaceSunken,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        side: BorderSide(
          color: selected ? p.accent : p.border,
          width: selected ? 1.8 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 36,
                decoration: BoxDecoration(
                  color: preview.sidebarBg,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: preview.sidebarBorder),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: preview.accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: preview.sidebarText.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: preview.sidebarText.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            style.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.labelLarge.copyWith(
                              fontSize: 13,
                              color: p.textPrimary,
                            ),
                          ),
                        ),
                        if (selected)
                          Icon(
                            Icons.check_circle_rounded,
                            size: 16,
                            color: p.accentInk,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      style.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodySmall.copyWith(
                        fontSize: 11,
                        color: p.textSecondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisplayScaleChip extends StatelessWidget {
  const _DisplayScaleChip({
    required this.scale,
    required this.selected,
    required this.onTap,
  });

  final AppDisplayScale scale;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final percent = '${(scale.factor * 100).round()}%';

    return Material(
      key: ValueKey('theme-scale-${scale.id}'),
      color: selected ? p.accent : p.surfaceSunken,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.medium),
        side: BorderSide(color: selected ? p.accent : p.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                scale.label,
                style: AppTextStyles.labelMedium.copyWith(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: selected ? p.onAccent : p.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                percent,
                style: AppTextStyles.labelSmall.copyWith(
                  fontSize: 11,
                  color: selected
                      ? p.onAccent.withValues(alpha: 0.85)
                      : p.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
