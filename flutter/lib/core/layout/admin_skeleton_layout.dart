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
    this.loadMarkers = adminMarkers,
  });

  final String title;
  final String subtitle;
  final int selectedNavigationIndex;
  final Widget child;
  final ValueChanged<int>? onNavigationSelected;

  /// See [AppShell.loadMarkers].
  final Future<Map<int, int>> Function() loadMarkers;

  /// Flat sidebar index of Requisitions: 0 Overview, 1 User management,
  /// 2 Inventory, 3 Sales & POS, 4 Requisitions. Shared by [adminMarkers] and
  /// pinned by `sidebar_pattern_test.dart`.
  static const requisitionsIndex = 4;

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

  /// The admin groups, by the index each item ALREADY has: today's flat order
  /// with headings only, so no index moves.
  static const groups = [
    ('Overview', 0),
    ('People', 1),
    ('Operations', 2),
    ('Insights', 5),
    ('System', 6),
  ];

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      subtitle: subtitle,
      sections: _sections,
      selectedIndex: selectedNavigationIndex,
      loadMarkers: loadMarkers,
      onDestinationSelected:
          onNavigationSelected ??
          (index) => context.go(_navigationItems[index].$3),
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

/// Requisitions waiting for approval, the one live count on the admin menu
/// (ledger ruling, F4): SUBMITTED requisitions at index 4. Read once when the
/// shell mounts; a failure shows no marker rather than a false 0.
Future<Map<int, int>> adminMarkers() async {
  final requisitions = await RequisitionRepository().fetchRequisitions();
  return {
    AdminSkeletonLayout.requisitionsIndex: requisitions
        .where((row) => row.status.isAwaitingApproval)
        .length,
  };
}
