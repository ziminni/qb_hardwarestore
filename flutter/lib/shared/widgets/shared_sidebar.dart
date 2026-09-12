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

  final String label;
  final List<SharedSidebarDestination> destinations;
}

class SharedSidebar extends StatelessWidget {
  const SharedSidebar({
    super.key,
    required this.sections,
    required this.selectedIndex,
    this.onDestinationSelected,
  });

  final List<SharedSidebarSection> sections;
  final int selectedIndex;
  final ValueChanged<int>? onDestinationSelected;

  static const double width = 260;

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

      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: Material(
          color: selected ? colors.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          elevation: selected ? 1 : 0,
          child: ListTile(
            dense: true,
            visualDensity: const VisualDensity(vertical: -2),
            selected: selected,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
            ),
            horizontalTitleGap: AppSpacing.md,
            leading: Icon(destination.icon, size: 18),
            title: Text(
              destination.label,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            onTap: onDestinationSelected == null
                ? null
                : () => onDestinationSelected!(currentIndex),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xl,
      ),
      children: [
        for (
          var sectionIndex = 0;
          sectionIndex < sections.length;
          sectionIndex++
        ) ...[
          if (sectionIndex > 0) const SizedBox(height: AppSpacing.lg),
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
          for (final destination in sections[sectionIndex].destinations)
            buildDestination(destination, destinationIndex++),
        ],
      ],
    );
  }
}
