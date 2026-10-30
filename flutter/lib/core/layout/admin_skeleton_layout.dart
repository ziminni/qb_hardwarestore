import 'package:client/core/layout/app_shell.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminSkeletonLayout extends StatelessWidget {
  const AdminSkeletonLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selectedNavigationIndex,
    required this.child,
    this.onNavigationSelected,
  });

  final String title;
  final String subtitle;
  final int selectedNavigationIndex;
  final Widget child;
  final ValueChanged<int>? onNavigationSelected;

  static const _navigationItems = [
    ('Overview', Icons.dashboard_outlined, '/admin/dashboard'),
    ('User management', Icons.manage_accounts_outlined, '/admin/users'),
    ('Inventory', Icons.inventory_2_outlined, '/admin/inventory'),
    ('Sales & POS', Icons.point_of_sale_outlined, '/admin/sales'),
    ('Requisitions', Icons.receipt_long_outlined, '/admin/requisitions'),
    ('Reports', Icons.bar_chart_rounded, '/admin/reports'),
    ('Audit logs', Icons.history_rounded, '/admin/audit-logs'),
    ('Settings', Icons.settings_outlined, '/admin/settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      subtitle: subtitle,
      sections: [
        SharedSidebarSection(
          label: 'Administration',
          destinations: [
            for (final item in _navigationItems)
              SharedSidebarDestination(label: item.$1, icon: item.$2),
          ],
        ),
      ],
      selectedIndex: selectedNavigationIndex,
      onDestinationSelected: (index) {
        if (onNavigationSelected != null) {
          onNavigationSelected!(index);
        } else {
          context.go(_navigationItems[index].$3);
        }
      },
      fallbackName: 'Administrator',
      fallbackRole: 'Admin',
      child: child,
    );
  }
}
