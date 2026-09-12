import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:client/shared/widgets/system_brand.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    final auth = context.watch<AuthViewmodel>();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: colors.surfaceContainerLowest,
      body: Row(
        children: [
          Container(
            width: SharedSidebar.width,
            decoration: BoxDecoration(
              color: colors.surface,
              border: const Border(right: BorderSide(color: AppColors.border)),
            ),
            child: Column(
              children: [
                const SizedBox(
                  height: 72,
                  child: Center(
                    child: SystemBrand(
                      logoSize: 42,
                      fontSize: 14,
                      subtitle: '& CONSTRUCTION SUPPLIES',
                    ),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SharedSidebar(
                    sections: _navigationSections,
                    selectedIndex: selectedNavigationIndex,
                    onDestinationSelected: onNavigationSelected,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(auth.user?.fullName ?? 'Inventory Staff'),
                  subtitle: Text(
                    auth.user?.role.displayName ?? 'Inventory Staff',
                  ),
                  trailing: IconButton(
                    tooltip: 'Log out',
                    onPressed: auth.logout,
                    icon: const Icon(Icons.logout, size: 18),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 72,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    border: const Border(
                      bottom: BorderSide(color: AppColors.border),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              subtitle,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.notifications_none, size: 17),
                        label: const Text('Notifications'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
