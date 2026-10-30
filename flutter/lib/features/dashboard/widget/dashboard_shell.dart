import 'package:client/shared/widgets/app_shell.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';

/// The POS shell: a flat menu (no section headings) inside [AppShell].
class DashboardShell extends StatelessWidget {
  const DashboardShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selectedNavigationIndex,
    required this.navigationItems,
    required this.child,
    this.onNavigationSelected,
    this.scrollable = true,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final int selectedNavigationIndex;
  final List<DashboardNavigationItem> navigationItems;
  final Widget child;
  final ValueChanged<int>? onNavigationSelected;

  /// See [AppShell.scrollable].
  final bool scrollable;

  /// Widgets at the right end of the header (see [AppShell.actions]).
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      subtitle: subtitle,
      sections: [
        SharedSidebarSection(
          label: '',
          destinations: [
            for (final item in navigationItems)
              SharedSidebarDestination(label: item.label, icon: item.icon),
          ],
        ),
      ],
      selectedIndex: selectedNavigationIndex,
      onDestinationSelected: onNavigationSelected,
      scrollable: scrollable,
      actions: actions,
      child: child,
    );
  }
}

class DashboardNavigationItem {
  const DashboardNavigationItem(this.label, this.icon);

  final String label;
  final IconData icon;
}
