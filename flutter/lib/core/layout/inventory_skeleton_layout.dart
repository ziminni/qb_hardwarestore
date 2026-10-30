import 'package:client/shared/widgets/app_shell.dart';
import 'package:client/shared/widgets/notifications_button.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';

class InventorySkeletonLayout extends StatelessWidget {
  const InventorySkeletonLayout({
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

  static const _navigationSections = [
    SharedSidebarSection(
      label: 'Overview',
      destinations: [
        SharedSidebarDestination(
          label: 'Dashboard',
          icon: Icons.dashboard_outlined,
        ),
      ],
    ),
    SharedSidebarSection(
      label: 'Inventory',
      destinations: [
        SharedSidebarDestination(
          label: 'Products',
          icon: Icons.inventory_2_outlined,
        ),
        SharedSidebarDestination(
          label: 'Categories',
          icon: Icons.category_outlined,
        ),
        SharedSidebarDestination(
          label: 'Stock',
          icon: Icons.warehouse_outlined,
        ),
        SharedSidebarDestination(
          label: 'Stock movements',
          icon: Icons.swap_vert_rounded,
        ),
        SharedSidebarDestination(
          label: 'Low stock',
          icon: Icons.warning_amber_rounded,
        ),
      ],
    ),
    SharedSidebarSection(
      label: 'Purchasing',
      destinations: [
        SharedSidebarDestination(
          label: 'Purchases',
          icon: Icons.shopping_bag_outlined,
        ),
        SharedSidebarDestination(
          label: 'Suppliers',
          icon: Icons.local_shipping_outlined,
        ),
        // Receiving belongs to the purchasing flow (goods arrive against a PO),
        // and it needs its OWN destination: it used to occupy index 9, which
        // the sidebar renders as "Returns", so the Returns tab opened Receiving
        // and the three tabs after it were unreachable.
        SharedSidebarDestination(
          label: 'Receiving',
          icon: Icons.move_to_inbox_outlined,
        ),
      ],
    ),
    SharedSidebarSection(
      label: 'Sales',
      destinations: [
        SharedSidebarDestination(
          label: 'Sales',
          icon: Icons.shopping_cart_outlined,
        ),
        SharedSidebarDestination(label: 'Returns', icon: Icons.undo_rounded),
        SharedSidebarDestination(
          label: 'Reports',
          icon: Icons.bar_chart_rounded,
        ),
        SharedSidebarDestination(
          label: 'Settings',
          icon: Icons.settings_outlined,
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      subtitle: subtitle,
      sections: _navigationSections,
      selectedIndex: selectedNavigationIndex,
      onDestinationSelected: onNavigationSelected,
      actions: const [NotificationsButton()],
      fallbackUserName: 'Inventory Staff',
      fallbackRoleLabel: 'Inventory Staff',
      child: child,
    );
  }
}
