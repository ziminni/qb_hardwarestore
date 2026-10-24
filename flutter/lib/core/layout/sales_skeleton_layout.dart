import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/constants/app_spacing.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/shared/widgets/notifications_button.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:client/shared/widgets/system_brand.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class SalesSkeletonLayout extends StatelessWidget {
  const SalesSkeletonLayout({
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

  static const navigationSections = [
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
      label: 'Selling',
      destinations: [
        SharedSidebarDestination(
          label: 'Transactions',
          icon: Icons.receipt_long_outlined,
        ),
        SharedSidebarDestination(
          label: 'Quotations',
          icon: Icons.request_quote_outlined,
        ),
        SharedSidebarDestination(
          label: 'Sales orders',
          icon: Icons.assignment_outlined,
        ),
      ],
    ),
    SharedSidebarSection(
      label: 'Customers',
      destinations: [
        SharedSidebarDestination(
          label: 'Receivables',
          icon: Icons.account_balance_wallet_outlined,
        ),
      ],
    ),
    SharedSidebarSection(
      label: 'After Sales',
      destinations: [
        SharedSidebarDestination(
          label: 'Returns & refunds',
          icon: Icons.assignment_return_outlined,
        ),
      ],
    ),
    SharedSidebarSection(
      label: 'Insights',
      destinations: [
        SharedSidebarDestination(
          label: 'Reports',
          icon: Icons.bar_chart_outlined,
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
                    sections: navigationSections,
                    selectedIndex: selectedNavigationIndex,
                    onDestinationSelected: onNavigationSelected,
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  title: Text(auth.user?.fullName ?? 'Sales Staff'),
                  subtitle: Text(auth.user?.roleLabel ?? 'Sales Staff'),
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
                      const NotificationsButton(),
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
