import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:flutter/material.dart';

class SharedSidebarDestination {
  const SharedSidebarDestination({required this.label, required this.icon});

  final String label;
  final IconData icon;
}

class SharedSidebarSection {
  const SharedSidebarSection({required this.label, required this.destinations});

  /// Heading above the section. Empty means no heading (a flat menu).
  final String label;
  final List<SharedSidebarDestination> destinations;
}

class SharedSidebar extends StatelessWidget {
  const SharedSidebar({
    super.key,
    required this.sections,
    required this.selectedIndex,
    this.onDestinationSelected,
    this.collapsed = false,
  });

  final List<SharedSidebarSection> sections;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;

  /// Icon rail: icons only, each label moved into a tooltip (which also
  /// carries it for screen readers).
  final bool collapsed;

  static const double width = 260;
  static const double railWidth = 76;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    var destinationIndex = 0;

    Widget buildDestination(
      SharedSidebarDestination destination,
      int currentIndex,
    ) {
      final selected = currentIndex == selectedIndex;
      final onTap = onDestinationSelected == null
          ? null
          : () => onDestinationSelected!(currentIndex);

      if (collapsed) {
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: Tooltip(
            message: destination.label,
            preferBelow: false,
            child: Material(
              color: selected ? AppColors.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadii.medium),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadii.medium),
                onTap: onTap,
                child: SizedBox(
                  height: 48,
                  child: Center(
                    child: Icon(
                      destination.icon,
                      size: 22,
                      color: selected ? AppColors.textPrimary : null,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Material(
          color: selected ? AppColors.selected : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: ListTile(
            dense: true,
            selected: selected,
            selectedColor: AppColors.textPrimary,
            minTileHeight: 44,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
            ),
            horizontalTitleGap: AppSpacing.md,
            leading: Icon(destination.icon, size: 19),
            title: Text(
              destination.label,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 13,
                color: selected ? AppColors.textPrimary : null,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            onTap: onTap,
          ),
        ),
      );
    }

    return ListView(
      padding: collapsed
          ? const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.lg,
            )
          : const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xl,
            ),
      children: [
        for (
          var sectionIndex = 0;
          sectionIndex < sections.length;
          sectionIndex++
        ) ...[
          if (collapsed) ...[
            if (sectionIndex > 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Divider(height: 1),
              ),
          ] else ...[
            if (sectionIndex > 0) const SizedBox(height: AppSpacing.lg),
            if (sections[sectionIndex].label.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Text(
                  sections[sectionIndex].label.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
          for (final destination in sections[sectionIndex].destinations)
            buildDestination(destination, destinationIndex++),
        ],
      ],
    );
  }
}
