import 'package:client/shared/widgets/app_shell.dart';
import 'package:client/shared/widgets/notifications_button.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';

class SalesSkeletonLayout extends StatelessWidget {
  const SalesSkeletonLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selectedNavigationIndex,
    required this.child,
    this.onNavigationSelected,
    this.scrollable = true,
  });

  final String title;
  final String subtitle;
  final int selectedNavigationIndex;
  final Widget child;
  final ValueChanged<int>? onNavigationSelected;

  /// See [AppShell.scrollable]. A page whose list must build rows lazily passes
  /// false and gives the list an `Expanded` slot of its own.
  final bool scrollable;

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
    // Appended last: the sidebar index is the position in this list, so a
    // new group anywhere else would renumber every tab after it.
    //
    // Approvals used to sit at index 7 and is gone (decision 01): requests are
    // approved in CPMS, so Staff moved up into the free slot.
    SharedSidebarSection(
      label: 'Management',
      destinations: [
        SharedSidebarDestination(
          label: 'Staff',
          icon: Icons.manage_accounts_outlined,
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      subtitle: subtitle,
      sections: navigationSections,
      selectedIndex: selectedNavigationIndex,
      onDestinationSelected: onNavigationSelected,
      scrollable: scrollable,
      actions: const [NotificationsButton()],
      fallbackUserName: 'Sales Staff',
      fallbackRoleLabel: 'Sales Staff',
      child: child,
    );
  }
}
