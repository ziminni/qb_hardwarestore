import 'package:client/core/layout/app_shell.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';

class DashboardShell extends StatelessWidget {
  const DashboardShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selectedNavigationIndex,
    required this.navigationItems,
    required this.child,
  });

  final String title;
  final String subtitle;
  final int selectedNavigationIndex;
  final List<DashboardNavigationItem> navigationItems;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      subtitle: subtitle,
      sections: [
        SharedSidebarSection(
          label: 'Point of sale',
          destinations: [
            for (final item in navigationItems)
              SharedSidebarDestination(label: item.label, icon: item.icon),
          ],
        ),
      ],
      selectedIndex: selectedNavigationIndex,
      onDestinationSelected: (_) {},
      fallbackName: '[ USER NAME ]',
      fallbackRole: '[ ROLE ]',
      child: child,
    );
  }
}

class DashboardNavigationItem {
  const DashboardNavigationItem(this.label, this.icon);

  final String label;
  final IconData icon;
}
