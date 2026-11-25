import 'package:flutter/material.dart';

/// Shared visual tokens and building blocks matching the Stitch
/// "QB Hardware - Command & Operations Suite" aesthetic:
/// cool light-blue canvas, pure white 16px-radius elevated cards, royal blue
/// accents, tinted icon badges, bold tabular numerals, and status pills.
class StitchColors {
  StitchColors._();

  static const Color primary = Color(0xFF1E40AF);
  static const Color primaryDeep = Color(0xFF00288E);
  static const Color primaryTint = Color(0xFFDBEAFE);
  static const Color primarySoft = Color(0xFFEFF6FF);

  static const Color surfaceCanvas = Color(0xFFF4F7FF);
  static const Color card = Color(0xFFFFFFFF);
  static const Color cardBorder = Color(0xFFE2E8F0);
  static const Color divider = Color(0xFFE8EEF8);

  static const Color ink = Color(0xFF0B1C30);
  static const Color inkMuted = Color(0xFF5B6B82);

  static const Color success = Color(0xFF059669);
  static const Color successTint = Color(0xFFDCFCE7);
  static const Color successMint = Color(0xFF6FFBB8);
  static const Color successInk = Color(0xFF065F46);

  static const Color warning = Color(0xFFD97706);
  static const Color warningTint = Color(0xFFFEF3C7);
  static const Color warningInk = Color(0xFF92400E);

  static const Color danger = Color(0xFFDC2626);
  static const Color dangerTint = Color(0xFFFEE2E2);
  static const Color dangerInk = Color(0xFF991B1B);
}

enum StitchTone { primary, success, warning, danger, neutral }

({Color fg, Color bg, Color accent}) stitchTonePalette(StitchTone tone) =>
    switch (tone) {
      StitchTone.primary => (
        fg: StitchColors.primary,
        bg: StitchColors.primaryTint,
        accent: StitchColors.primary,
      ),
      StitchTone.success => (
        fg: StitchColors.successInk,
        bg: StitchColors.successTint,
        accent: StitchColors.success,
      ),
      StitchTone.warning => (
        fg: StitchColors.warningInk,
        bg: StitchColors.warningTint,
        accent: StitchColors.warning,
      ),
      StitchTone.danger => (
        fg: StitchColors.dangerInk,
        bg: StitchColors.dangerTint,
        accent: StitchColors.danger,
      ),
      StitchTone.neutral => (
        fg: StitchColors.inkMuted,
        bg: const Color(0xFFF1F5F9),
        accent: StitchColors.inkMuted,
      ),
    };

/// Compact rounded pill badge used inside KPI cards, headers, and table cells.
class StitchPill extends StatelessWidget {
  const StitchPill({
    super.key,
    required this.label,
    this.tone = StitchTone.primary,
    this.icon,
  });

  final String label;
  final StitchTone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final palette = stitchTonePalette(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: palette.bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: palette.fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: palette.fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stitch-style elevated white KPI card with uppercase overline, top-right
/// tinted icon badge, large bold tabular value, optional subtitle, optional
/// progress bar, and optional footer pills.
class StitchKpiCard extends StatelessWidget {
  const StitchKpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone = StitchTone.primary,
    this.subtitle,
    this.pillLabel,
    this.pillTone,
    this.secondaryPillLabel,
    this.secondaryPillTone,
    this.progress,
    this.valueColor,
    this.compact = false,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final StitchTone tone;
  final String? subtitle;
  final String? pillLabel;
  final StitchTone? pillTone;
  final String? secondaryPillLabel;
  final StitchTone? secondaryPillTone;
  final double? progress;
  final Color? valueColor;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = stitchTonePalette(tone);
    final body = Container(
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
          : const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StitchColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StitchColors.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: StitchColors.inkMuted,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: compact ? 22 : 32,
                height: compact ? 22 : 32,
                decoration: BoxDecoration(
                  color: palette.bg,
                  borderRadius: BorderRadius.circular(compact ? 6 : 10),
                ),
                child: Icon(icon, size: compact ? 13 : 17, color: palette.fg),
              ),
            ],
          ),
          SizedBox(height: compact ? 3 : 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: compact ? 18 : 24,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: valueColor ?? StitchColors.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            SizedBox(height: compact ? 1 : 4),
            Text(
              subtitle!,
              maxLines: compact ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11.5 : 12,
                color: StitchColors.inkMuted,
              ),
            ),
          ],
          if (progress != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: progress!.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: const Color(0xFFE2E8F0),
                valueColor: AlwaysStoppedAnimation<Color>(palette.accent),
              ),
            ),
          ],
          if (pillLabel != null || secondaryPillLabel != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (pillLabel != null)
                  StitchPill(label: pillLabel!, tone: pillTone ?? tone),
                if (secondaryPillLabel != null)
                  StitchPill(
                    label: secondaryPillLabel!,
                    tone: secondaryPillTone ?? StitchTone.neutral,
                  ),
              ],
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: body,
      ),
    );
  }
}

/// Stitch-style white section card with optional numbered overline
/// (e.g. `01 / FINANCIAL VELOCITY`), title, subtitle, trailing action/pill, and
/// body.
class StitchSectionCard extends StatelessWidget {
  const StitchSectionCard({
    super.key,
    required this.title,
    this.overline,
    this.subtitle,
    this.icon,
    this.trailing,
    required this.child,
  });

  final String title;
  final String? overline;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: StitchColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: StitchColors.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A0F172A),
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: StitchColors.primarySoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        icon,
                        size: 18,
                        color: StitchColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (overline != null)
                          Text(
                            overline!.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.7,
                              color: StitchColors.primary,
                            ),
                          ),
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: StitchColors.ink,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: StitchColors.inkMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Stitch-style left-accented tinted sub-card used for dual-stream OR vs OS
/// cards and FIFO pipeline cards.
class StitchAccentBox extends StatelessWidget {
  const StitchAccentBox({
    super.key,
    required this.accentColor,
    this.backgroundColor = StitchColors.surfaceCanvas,
    required this.child,
  });

  final Color accentColor;
  final Color backgroundColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StitchColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accentColor),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Crisp segmented pill bar matching Stitch's top timeframe selector
/// (`Daily (Today)` | `Weekly (7 Days)` | `Monthly (MTD)`).
class StitchSegmentedBar<T> extends StatelessWidget {
  const StitchSegmentedBar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelected,
  });

  final List<({T value, String label, Key? key})> items;
  final T selected;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: StitchColors.surfaceCanvas,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StitchColors.cardBorder),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (final item in items)
            _SegmentedItem(
              key: item.key,
              label: item.label,
              active: item.value == selected,
              onTap: () => onSelected(item.value),
            ),
        ],
      ),
    );
  }
}

class _SegmentedItem extends StatelessWidget {
  const _SegmentedItem({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? StitchColors.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: active ? Colors.white : StitchColors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}
