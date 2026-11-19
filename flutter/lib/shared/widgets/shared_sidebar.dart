import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:flutter/material.dart';

class SharedSidebarDestination {
  const SharedSidebarDestination({
    required this.label,
    required this.icon,
    this.id,
  });

  final String label;
  final IconData icon;

  /// Stable identity of the page across areas (Phase 2 F2). Merged rendering
  /// highlights and counts by this instead of by position: the same page opened
  /// from a narrower area lights the one row the widest area owns. Null on a
  /// caller-built menu, which then keeps the flat-index behaviour.
  final String? id;
}

class SharedSidebarSection {
  const SharedSidebarSection({required this.label, required this.destinations});

  /// Heading above the section. Empty means no heading (a flat menu).
  final String label;
  final List<SharedSidebarDestination> destinations;
}

class SharedSidebar extends StatefulWidget {
  const SharedSidebar({
    super.key,
    required this.sections,
    required this.selectedIndex,
    this.selectedId,
    this.onDestinationSelected,
    this.collapsed = false,
    this.markers = const {},
    this.markersById = const {},
  });

  final List<SharedSidebarSection> sections;
  final int selectedIndex;

  /// The page to highlight, by [SharedSidebarDestination.id]. When set it wins
  /// over [selectedIndex]: a merged list has no per-area index to compare, and
  /// an id survives the de-duplication that renumbers every row after it.
  final String? selectedId;

  final ValueChanged<int>? onDestinationSelected;

  /// A live count per destination, keyed by the same flat index as
  /// [selectedIndex]. Missing, zero or negative draws nothing at all: a marker
  /// reading "0" is a claim about a queue, and a wrong one is worse than none.
  final Map<int, int> markers;

  /// The same live counts keyed by [SharedSidebarDestination.id], for the merged
  /// list. A [[markers]] entry still wins when both name the row.
  final Map<String, int> markersById;

  /// Icon rail: icons only, each label moved into a tooltip (which also
  /// carries it for screen readers).
  final bool collapsed;

  static const double width = 260;
  static const double railWidth = 76;

  @override
  State<SharedSidebar> createState() => _SharedSidebarState();
}

class _SharedSidebarState extends State<SharedSidebar> {
  int? _hoveredIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = AppPalette.of(context);
    final sections = widget.sections;
    final collapsed = widget.collapsed;
    final selectedIndex = widget.selectedIndex;
    final selectedId = widget.selectedId;
    final onDestinationSelected = widget.onDestinationSelected;
    final markers = widget.markers;
    final markersById = widget.markersById;
    var destinationIndex = 0;

    final selectedFill = p.sidebarIsLight
        ? p.selected
        : p.accent.withValues(alpha: 0.14);
    final selectedBorder = p.sidebarIsLight
        ? p.accent.withValues(alpha: 0.45)
        : p.accent.withValues(alpha: 0.32);
    final hoverFill = p.sidebarIsLight
        ? p.selected.withValues(alpha: 0.45)
        : AppColors.brandWhite.withValues(alpha: 0.05);

    Widget buildDestination(
      SharedSidebarDestination destination,
      int currentIndex,
    ) {
      // An id names the page whatever its position; without one (a
      // caller-built menu) the flat index still does.
      final id = destination.id;
      final selected = selectedId != null && id != null
          ? id == selectedId
          : currentIndex == selectedIndex;
      final hovered = _hoveredIndex == currentIndex;
      final foreground = selected
          ? p.sidebarActiveText
          : hovered
          ? p.sidebarHoverText
          : p.sidebarText;
      final iconColor = selected
          ? p.sidebarActiveText
          : hovered
          ? (p.sidebarIsLight
                ? p.accentInk
                : p.accentLight.withValues(alpha: 0.9))
          : p.sidebarText.withValues(alpha: 0.88);
      final onTap = onDestinationSelected == null
          ? null
          : () => onDestinationSelected(currentIndex);
      final count =
          (id == null ? null : markersById[id]) ?? markers[currentIndex] ?? 0;

      if (collapsed) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Tooltip(
                message: destination.label,
                preferBelow: false,
                child: Material(
                  color: selected ? selectedFill : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                    side: selected
                        ? BorderSide(color: selectedBorder)
                        : hovered
                        ? BorderSide(
                            color: p.sidebarBorder.withValues(alpha: 0.9),
                          )
                        : BorderSide.none,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadii.medium),
                    onTap: onTap,
                    hoverColor: hoverFill,
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: Icon(
                          destination.icon,
                          size: 20,
                          color: iconColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (selected) const _ActiveBar(inset: 9),
              // The rail has no labels, so the count rides on the icon.
              if (count > 0)
                Positioned(
                  top: -3,
                  right: -2,
                  child: _MarkerCount(
                    index: currentIndex,
                    count: count,
                    onRail: true,
                  ),
                ),
            ],
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Stack(
          children: [
            Material(
              color: selected ? selectedFill : Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.medium),
                side: selected
                    ? BorderSide(color: selectedBorder)
                    : BorderSide.none,
              ),
              child: ListTile(
                dense: true,
                selected: selected,
                selectedColor: p.sidebarActiveText,
                selectedTileColor: Colors.transparent,
                hoverColor: hoverFill,
                minTileHeight: 42,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.medium),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                horizontalTitleGap: 11,
                leading: Icon(destination.icon, size: 18, color: iconColor),
                title: Text(
                  destination.label,
                  overflow: TextOverflow.ellipsis,
                  style: (theme.textTheme.bodySmall ?? AppTextStyles.bodySmall)
                      .copyWith(
                        fontSize: 13,
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                ),
                trailing: count > 0
                    ? _MarkerCount(index: currentIndex, count: count)
                    : null,
                onTap: onTap,
              ),
            ),
            if (selected) const _ActiveBar(inset: 9),
          ],
        ),
      );
    }

    Widget destinationRegion(SharedSidebarDestination destination, int index) {
      return MouseRegion(
        onEnter: (_) => setState(() => _hoveredIndex = index),
        onExit: (_) => setState(() => _hoveredIndex = null),
        child: buildDestination(destination, index),
      );
    }

    final headingAccent = p.sidebarIsLight
        ? p.accentInk
        : p.accent.withValues(alpha: 0.85);

    bool isSettingsDestination(SharedSidebarDestination destination) =>
        destination.label == 'Settings' ||
        (destination.id?.endsWith('.settings') ?? false);

    // Preserve every destination's original flat index (routing tables pin
    // these indices), while lifting Settings to a pinned bottom footer slot so
    // it sits at the very bottom of the sidebar in every role.
    final mainSections =
        <(String label, List<(SharedSidebarDestination, int)> items)>[];
    final bottomSettings = <(SharedSidebarDestination, int)>[];

    for (final section in sections) {
      final kept = <(SharedSidebarDestination, int)>[];
      for (final destination in section.destinations) {
        final index = destinationIndex++;
        if (isSettingsDestination(destination)) {
          bottomSettings.add((destination, index));
        } else {
          kept.add((destination, index));
        }
      }
      if (kept.isNotEmpty) {
        mainSections.add((section.label, kept));
      }
    }

    final pinSettingsFooter = bottomSettings.length == 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: collapsed
                ? const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  )
                : const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.lg,
                  ),
            children: [
              for (
                var sectionIndex = 0;
                sectionIndex < mainSections.length;
                sectionIndex++
              ) ...[
                if (collapsed) ...[
                  if (sectionIndex > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Divider(height: 1, color: p.sidebarBorder),
                    ),
                ] else ...[
                  if (sectionIndex > 0)
                    const SizedBox(height: AppSpacing.md + 2),
                  if (mainSections[sectionIndex].$1.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 1.5,
                            decoration: BoxDecoration(
                              color: headingAccent,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              mainSections[sectionIndex].$1.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  (theme.textTheme.labelSmall ??
                                          AppTextStyles.labelSmall)
                                      .copyWith(
                                        fontSize: 10,
                                        color: headingAccent,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 1.5,
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
                for (final (destination, index) in mainSections[sectionIndex].$2)
                  destinationRegion(destination, index),
              ],
              if (!pinSettingsFooter && bottomSettings.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Divider(height: 1, color: p.sidebarBorder),
                ),
                for (final (destination, index) in bottomSettings)
                  destinationRegion(destination, index),
              ],
            ],
          ),
        ),
        if (pinSettingsFooter) ...[
          Divider(height: 1, color: p.sidebarBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: destinationRegion(
              bottomSettings.single.$1,
              bottomSettings.single.$2,
            ),
          ),
        ],
      ],
    );
  }
}

/// The accent bar on the selected destination: a fill shape on the left edge,
/// drawn in the full sidebar and in the icon rail alike, so the current page
/// reads the same at every width.
class _ActiveBar extends StatelessWidget {
  const _ActiveBar({required this.inset});

  /// Vertical inset, so the bar is shorter than the row it marks.
  final double inset;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Positioned(
      left: 0,
      top: inset,
      bottom: inset,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 3),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          builder: (context, width, child) => Container(
            key: const ValueKey('sidebar-active-bar'),
            width: width,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [p.accentLight, p.accent],
              ),
              borderRadius: BorderRadius.circular(2),
              boxShadow: [
                BoxShadow(
                  color: p.accent.withValues(alpha: 0.4),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A live count beside its destination (or on its rail icon).
class _MarkerCount extends StatelessWidget {
  const _MarkerCount({
    required this.index,
    required this.count,
    this.onRail = false,
  });

  final int index;
  final int count;
  final bool onRail;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Container(
      key: ValueKey('sidebar-marker-$index'),
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: p.accent,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: onRail
            ? Border.all(color: p.sidebarBg, width: 1.5)
            : null,
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontFamily: AppTextStyles.outfitFont,
          fontSize: 11,
          height: 1.3,
          fontWeight: FontWeight.w700,
          color: p.onAccent,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
