import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/navigation/app_destinations.dart';
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
    this.loadMarkers = _noMarkers,
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

  /// The admin menu as the sidebar renders it, derived from [AppDestinations]
  /// (Phase 2 F1). Read by the index tests so they pin the menu production
  /// actually draws.
  static List<SharedSidebarSection> get navigationSections =>
      AppDestinations.sectionsFor(AppAreas.admin);

  /// The admin groups, by the index each destination ALREADY has, derived from
  /// [AppDestinations]: today's flat order with headings only, so no index moves.
  static List<(String, int)> get groups =>
      AppDestinations.groupsFor(AppAreas.admin);

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      subtitle: subtitle,
      sections: navigationSections,
      selectedIndex: selectedNavigationIndex,
      originArea: AppAreas.admin,
      scrollable: scrollable,
      onDestinationSelected:
          onNavigationSelected ?? (index) => _open(context, index),
      loadMarkers: loadMarkers,
      markers: markers,
      actions: const [NotificationsButton()],
      fallbackUserName: 'Administrator',
      fallbackRoleLabel: 'Admin',
      child: child,
    );
  }

  /// Taps that the page does not handle itself open the destination's own route.
  static void _open(BuildContext context, int index) {
    final route = AppDestinations.routeAt(AppAreas.admin, index);
    if (route != null) context.go(route);
  }
}

/// The Admin menu has no live count since Project requests left it (owner
/// 2026-11-18).
Future<Map<int, int>> _noMarkers() async => const {};
