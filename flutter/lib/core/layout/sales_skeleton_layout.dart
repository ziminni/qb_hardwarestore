import 'package:client/core/layout/app_shell.dart';
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
          label: 'Customers',
          icon: Icons.people_outline,
        ),
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
    return AppShell(
      title: title,
      subtitle: subtitle,
      sections: navigationSections,
      selectedIndex: selectedNavigationIndex,
      onDestinationSelected: onNavigationSelected,
      fallbackName: 'Sales Staff',
      fallbackRole: 'Sales Staff',
      child: child,
    );
  }
}
