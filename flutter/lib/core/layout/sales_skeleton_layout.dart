import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/navigation/merged_sidebar.dart';
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

  /// The store manager's menu as the sidebar renders it, derived from
  /// [AppDestinations] (Phase 2 F1). The flat index is the row's position, and a
  /// row that starts a heading starts a section, so grouping renumbers nothing.
  static List<SharedSidebarSection> get navigationSections =>
      AppDestinations.sectionsFor(AppAreas.sales);

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      subtitle: subtitle,
      sections: navigationSections,
      selectedIndex: selectedNavigationIndex,
      originArea: AppAreas.sales,
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
  final count = await waitingProjectRequestsCount();
  return {SalesSkeletonLayout.projectRequestsIndex: count};
}
