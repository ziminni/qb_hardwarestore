import 'package:client/data/repositories/requisition_repository.dart';
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
    this.loadMarkers = salesMarkers,
  });

  final String title;
  final String subtitle;
  final int selectedNavigationIndex;
  final Widget child;
  final ValueChanged<int>? onNavigationSelected;

  /// See [AppShell.loadMarkers].
  final Future<Map<int, int>> Function() loadMarkers;

  /// Flat sidebar index of Approvals: 0 Dashboard, 1 Transactions,
  /// 2 Quotations, 3 Sales orders, 4 Receivables, 5 Returns and refunds,
  /// 6 Reports, 7 Approvals. Shared by [salesMarkers] and pinned by
  /// `sidebar_pattern_test.dart`.
  static const approvalsIndex = 7;

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
    SharedSidebarSection(
      label: 'Management',
      destinations: [
        SharedSidebarDestination(
          label: 'Approvals',
          icon: Icons.fact_check_outlined,
        ),
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
      loadMarkers: loadMarkers,
      actions: const [NotificationsButton()],
      fallbackUserName: 'Sales Staff',
      fallbackRoleLabel: 'Sales Staff',
      child: child,
    );
  }
}

/// Requisitions waiting for approval, the one live count on the store manager's
/// menu (ledger ruling, F4): SUBMITTED requisitions at index 7 (Approvals, the
/// item appended for exactly this queue). Read once when the shell mounts; a
/// failure shows no marker rather than a false 0.
Future<Map<int, int>> salesMarkers() async {
  final requisitions = await RequisitionRepository().fetchRequisitions();
  return {
    SalesSkeletonLayout.approvalsIndex: requisitions
        .where((row) => row.status.isAwaitingApproval)
        .length,
  };
}
