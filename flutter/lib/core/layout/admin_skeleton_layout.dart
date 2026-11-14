import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/shared/widgets/app_shell.dart';
import 'package:client/shared/widgets/notifications_button.dart';
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

  /// Flat sidebar index of "Project requests" (decision 13). APPENDED in a
  /// final group, so no earlier index moves.
  static const int projectRequestsIndex = 7;

  static const _navigationItems = [
    ('Overview', Icons.dashboard_outlined, '/admin/dashboard'),
    ('User management', Icons.manage_accounts_outlined, '/admin/users'),
    ('Inventory', Icons.inventory_2_outlined, '/admin/inventory'),
    ('Sales & POS', Icons.point_of_sale_outlined, '/admin/sales'),
    ('Reports', Icons.bar_chart_rounded, '/admin/reports'),
    ('Audit logs', Icons.history_rounded, '/admin/audit-logs'),
    ('Settings', Icons.settings_outlined, '/admin/settings'),
    // Phase 1b (decisions 09, 10 and 13): the store answers CPMS's material
    // requests here too. Appended, in a group of its own below. The label is
    // short because "Requests from projects" clipped to "Requests from p…"
    // beside its count badge; the page title keeps the long form.
    ('Project requests', Icons.fact_check_outlined, '/admin/project-requests'),
    // Phase 5 F2: supplier payables. Appended, in a group of its own, so no
    // earlier index moves.
    ('Payables', Icons.account_balance_wallet_outlined, '/admin/payables'),
    // Phase 5 F3: customer deliveries. Appended, in a group of its own, so no
    // earlier index moves.
    ('Deliveries', Icons.local_shipping_outlined, '/admin/deliveries'),
    // Phase 5 F4: the shop's pick-up points. Appended LAST, in a group of its
    // own, so no earlier index moves.
    ('Storage locations', Icons.warehouse_outlined, '/admin/storage-locations'),
    // Phase 9 F3: stock transfers. Appended AFTER Storage locations, in its own
    // group, so every index above keeps its number.
    ('Transfers', Icons.swap_horiz_rounded, '/admin/transfers'),
  ];

  /// The admin groups, by the index each item ALREADY has: today's flat order
  /// with headings only, so no index moves.
  static const groups = [
    ('Overview', 0),
    ('People', 1),
    ('Operations', 2),
    ('Insights', 4),
    ('System', 5),
    // A new final group rather than another row under System: the queue is a
    // different job, and a new heading renumbers nothing because it is last.
    ('Projects', 7),
    ('Payables', 8),
    ('Deliveries', 9),
    // Phase 5 F4: appended last, so every index above keeps its number.
    ('Locations', 10),
    // Phase 9 F3: appended after Locations for the same reason.
    ('Transfers', 11),
  ];

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      subtitle: subtitle,
      sections: _sections,
      selectedIndex: selectedNavigationIndex,
      scrollable: scrollable,
      onDestinationSelected:
          onNavigationSelected ??
          (index) => context.go(_navigationItems[index].$3),
      loadMarkers: loadMarkers,
      markers: markers,
      actions: const [NotificationsButton()],
      fallbackUserName: 'Administrator',
      fallbackRoleLabel: 'Admin',
      child: child,
    );
  }

  static List<SharedSidebarSection> get _sections => [
    for (var group = 0; group < groups.length; group++)
      SharedSidebarSection(
        label: groups[group].$1,
        destinations: [
          for (final item in _navigationItems.sublist(
            groups[group].$2,
            group + 1 < groups.length
                ? groups[group + 1].$2
                : _navigationItems.length,
          ))
            SharedSidebarDestination(label: item.$1, icon: item.$2),
        ],
      ),
  ];
}

/// How many requests are waiting for the store, for the sidebar badge.
///
/// The server's own `count` for `?status=WAITING` (no page walk), read when the
/// shell mounts. A failed read throws and [AppShell] draws nothing: a badge
/// reading 0 is a claim that the queue is empty, which a failed read has not
/// established.
Future<Map<int, int>> projectRequestsMarkers() async {
  final count = await RequisitionRepository().waitingCount();
  return {AdminSkeletonLayout.projectRequestsIndex: count};
}
