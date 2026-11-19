import 'package:client/core/constants/app_spacing.dart';
import 'package:client/core/theme/app_palette.dart';
import 'package:client/shared/widgets/app_panel.dart';
import 'package:flutter/material.dart';

/// Width of the side menu on a wide window, matching Admin & POS Settings.
const double _menuWidth = 220;

/// Below this width, the side menu collapses to a horizontal scrolling tab bar.
const double _sideMenuBreakpoint = 760;

/// Maximum reading width of the open section on wide monitors.
const double _readingWidth = 720;

/// One section entry rendered in [SettingsSideLayout].
class SettingsSideSection {
  const SettingsSideSection({
    required this.id,
    required this.label,
    required this.icon,
    required this.description,
    required this.builder,
    this.group,
  });

  final String id;
  final String label;
  final IconData icon;
  final String description;
  final String? group;
  final WidgetBuilder builder;
}

/// Shared GitHub-style settings layout used across Admin, POS, Store Manager,
/// and Stock Manager Settings: grouped side tabs on the left (active tab marked
/// with an accent bar) and the open section with heading, description, and rule
/// on the right. Collapses cleanly into a horizontal tab strip below 760 px.
class SettingsSideLayout extends StatefulWidget {
  const SettingsSideLayout({
    super.key,
    required this.keyPrefix,
    required this.sections,
    this.initialIndex = 0,
  });

  final String keyPrefix;
  final List<SettingsSideSection> sections;
  final int initialIndex;

  @override
  State<SettingsSideLayout> createState() => _SettingsSideLayoutState();
}

class _SettingsSideLayoutState extends State<SettingsSideLayout> {
  late int _selectedIndex = widget.initialIndex.clamp(
    0,
    widget.sections.length - 1,
  );

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final section = widget.sections[_selectedIndex];

    return LayoutBuilder(
      builder: (context, slot) {
        final wide = slot.maxWidth >= _sideMenuBreakpoint;
        final menu = _SideMenu(
          keyPrefix: widget.keyPrefix,
          sections: widget.sections,
          selectedIndex: _selectedIndex,
          vertical: wide,
          onSelect: (index) => setState(() => _selectedIndex = index),
        );
        final body = ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _readingWidth),
          child: Column(
            key: ValueKey('${widget.keyPrefix}-section-${section.id}'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                section.label,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                section.description,
                style: TextStyle(color: p.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.lg),
              section.builder(context),
            ],
          ),
        );

        if (!wide) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              menu,
              const SizedBox(height: AppSpacing.lg),
              body,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: _menuWidth, child: menu),
            const SizedBox(width: AppSpacing.xl),
            Expanded(
              child: Align(alignment: Alignment.topLeft, child: body),
            ),
          ],
        );
      },
    );
  }
}

class _SideMenu extends StatelessWidget {
  const _SideMenu({
    required this.keyPrefix,
    required this.sections,
    required this.selectedIndex,
    required this.vertical,
    required this.onSelect,
  });

  final String keyPrefix;
  final List<SettingsSideSection> sections;
  final int selectedIndex;
  final bool vertical;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    final items = [
      for (final (index, section) in sections.indexed)
        _SideMenuItem(
          keyPrefix: keyPrefix,
          section: section,
          selected: index == selectedIndex,
          onTap: () => onSelect(index),
        ),
    ];

    if (!vertical) {
      return SingleChildScrollView(
        key: ValueKey('$keyPrefix-menu'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final item in items) ...[
              item,
              const SizedBox(width: AppSpacing.xs),
            ],
          ],
        ),
      );
    }

    return Column(
      key: ValueKey('$keyPrefix-menu'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, section) in sections.indexed) ...[
          if (section.group != null) ...[
            if (index > 0) ...[
              const SizedBox(height: AppSpacing.md),
              const Divider(height: 1),
              const SizedBox(height: AppSpacing.md),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.xs,
              ),
              child: Text(
                section.group!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: p.textSecondary,
                ),
              ),
            ),
          ],
          items[index],
          const SizedBox(height: 2),
        ],
      ],
    );
  }
}

class _SideMenuItem extends StatelessWidget {
  const _SideMenuItem({
    required this.keyPrefix,
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final String keyPrefix;
  final SettingsSideSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Material(
      key: ValueKey('$keyPrefix-menu-${section.id}'),
      color: selected ? p.selected : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          selected: selected,
          button: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 3,
                height: 36,
                color: selected ? p.accent : Colors.transparent,
              ),
              const SizedBox(width: AppSpacing.md - 3),
              Icon(
                section.icon,
                size: 18,
                color: selected ? p.textPrimary : p.textSecondary,
              ),
              const SizedBox(width: AppSpacing.sm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(
                  section.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? p.textPrimary : p.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared read-only store details card (same literals across Admin, Manager,
/// and Stocker settings screens — decisions D-03, D10).
class StoreInformationPanel extends StatelessWidget {
  const StoreInformationPanel({super.key, required this.footerNote});

  static const storeName = 'QB Hardware & Construction Supplies';
  static const storeEmail = 'contact@qbhardware.com';
  static const storePhone = '+63 912 345 6789';

  final String footerNote;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StoreFactField(label: 'Store name', value: storeName),
          const SizedBox(height: AppSpacing.lg),
          const _StoreFactField(label: 'Contact email', value: storeEmail),
          const SizedBox(height: AppSpacing.lg),
          const _StoreFactField(label: 'Contact number', value: storePhone),
          const SizedBox(height: AppSpacing.lg),
          Text(
            footerNote,
            style: TextStyle(fontSize: 12, color: p.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _StoreFactField extends StatelessWidget {
  const _StoreFactField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = AppPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: p.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(value, style: TextStyle(fontSize: 15, color: p.textPrimary)),
      ],
    );
  }
}
