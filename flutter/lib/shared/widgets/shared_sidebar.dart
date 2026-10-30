import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_durations.dart';
import 'package:client/core/constants/app_radii.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/constants/app_text_styles.dart';
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

// Navigation list for the dark app shell sidebar.
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
    var destinationIndex = 0;

    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xl,
      ),
      children: [
        for (
          var sectionIndex = 0;
          sectionIndex < sections.length;
          sectionIndex++
        ) ...[
          if (sectionIndex > 0) const SizedBox(height: AppSpacing.xl),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Text(
              sections[sectionIndex].label.toUpperCase(),
              style: AppTextStyles.labelSmall.copyWith(
                fontSize: 10,
                color: AppColors.brandGold.withValues(alpha: 0.75),
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final destination in sections[sectionIndex].destinations)
            _buildItem(destination, destinationIndex++),
        ],
      ],
    );
  }

  Widget _buildItem(SharedSidebarDestination destination, int index) {
    return _SidebarItem(
      destination: destination,
      selected: index == selectedIndex,
      onTap: onDestinationSelected == null
          ? null
          : () => onDestinationSelected!(index),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final SharedSidebarDestination destination;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final foreground = selected
        ? AppColors.brandGoldLight
        : _hovered
        ? AppColors.brandWhite
        : AppColors.chromeText;
    final background = selected
        ? AppColors.brandGold.withValues(alpha: 0.14)
        : _hovered
        ? AppColors.brandWhite.withValues(alpha: 0.05)
        : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Semantics(
        button: true,
        selected: selected,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          cursor: widget.onTap == null
              ? MouseCursor.defer
              : SystemMouseCursors.click,
          child: GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: AppDurations.fast,
              height: 40,
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(AppRadii.small + 2),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: AppDurations.fast,
                    width: 3,
                    height: selected ? 20 : 0,
                    decoration: BoxDecoration(
                      color: AppColors.brandGold,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Icon(widget.destination.icon, size: 18, color: foreground),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      widget.destination.label,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        fontSize: 13,
                        color: foreground,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
