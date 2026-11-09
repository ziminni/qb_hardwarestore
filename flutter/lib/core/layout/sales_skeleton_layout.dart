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
    this.scrollable = true,
    this.loadMarkers = projectRequestsMarkers,
    this.markers,
  });

  final String title;
  final String subtitle;
  final int selectedNavigationIndex;
  final Widget child;
  final ValueChanged<int>? onNavigationSelected;

  /// See [AppShell.scrollable]. A page whose list must build rows lazily passes
  /// false and gives the list an `Expanded` slot of its own.
  final bool scrollable;

  /// See [AppShell.loadMarkers]: the waiting-request count, read once when the
  /// shell mounts. A failed read draws no badge at all.
  final Future<Map<int, int>> Function() loadMarkers;

  /// See [AppShell.markers]. The queue page passes its OWN fresh count, so a
  /// decision taken on that screen updates the badge immediately.
  final Map<int, int>? markers;

  /// Flat sidebar index of "Project requests" (decision 13). APPENDED in
  /// its own section after Staff, so no earlier index moves — read by
  /// [projectRequestsMarkers] and pinned by the routing tests, because marking
  /// or navigating the wrong row is invisible in a test that only checks "a
  /// badge appeared".
  static const int projectRequestsIndex = 8;

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
    // Phase 1b (decisions 09, 10 and 13): the store answers CPMS's material
    // requests here. Appended in a section of its own for the same reason as
    // Staff: the sidebar index IS the position in this list.
    //
    // The label is short because "Requests from projects" clipped to
    // "Requests from p…" beside its count badge; the page title keeps the
    // long form.
    SharedSidebarSection(
      label: 'Projects',
      destinations: [
        SharedSidebarDestination(
          label: 'Project requests',
          icon: Icons.fact_check_outlined,
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
      markers: markers,
      scrollable: scrollable,
      actions: const [NotificationsButton()],
      fallbackUserName: 'Sales Staff',
      fallbackRoleLabel: 'Sales Staff',
      child: child,
    );
  }
}

/// How many requests are waiting for the store, for the sidebar badge.
///
/// The server's own `count` for `?status=WAITING` (no page walk), read when the
/// shell mounts. A failed read throws and [AppShell] draws nothing: a badge
/// reading 0 is a claim that the queue is empty, which a failed read has not
/// established.
Future<Map<int, int>> projectRequestsMarkers() async {
  final count = await RequisitionRepository().waitingCount();
  return {SalesSkeletonLayout.projectRequestsIndex: count};
}
