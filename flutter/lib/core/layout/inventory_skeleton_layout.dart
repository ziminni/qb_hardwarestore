import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/core/navigation/merged_sidebar.dart';
import 'package:client/shared/widgets/app_shell.dart';
import 'package:client/shared/widgets/notifications_button.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';

class InventorySkeletonLayout extends StatelessWidget {
  const InventorySkeletonLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selectedNavigationIndex,
    required this.child,
    this.onNavigationSelected,
    this.scrollable = true,
    this.loadMarkers = stockManagerMarkers,
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

  /// See [AppShell.loadMarkers].
  final Future<Map<int, int>> Function() loadMarkers;

  /// See [AppShell.markers]. A page that already holds the live count (Low
  /// stock and its open alerts) passes it here, so the badge follows the store
  /// the page resolves through instead of a one-off read at mount.
  final Map<int, int>? markers;

  /// Flat sidebar index of Low stock, the destination the open-alert marker
  /// belongs to: 0 Dashboard, 1 Products, 2 Categories, 3 Stock,
  /// 4 Stock adjustments, 5 Low stock. Read by [stockManagerMarkers] and pinned by
  /// `sidebar_pattern_test.dart`, because marking the wrong row is invisible in
  /// a widget test that only checks "a marker appeared".
  static const lowStockIndex = 5;

  /// The stock manager's menu as the sidebar renders it, derived from
  /// [AppDestinations] (Phase 2 F1). Read by the index tests so they pin the
  /// menu production actually draws.
  static List<SharedSidebarSection> get navigationSections =>
      AppDestinations.sectionsFor(AppAreas.inventory);

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      subtitle: subtitle,
      sections: navigationSections,
      selectedIndex: selectedNavigationIndex,
      originArea: AppAreas.inventory,
      onDestinationSelected: onNavigationSelected,
      loadMarkers: loadMarkers,
      markers: markers,
      scrollable: scrollable,
      actions: const [NotificationsButton()],
      fallbackUserName: 'Inventory Staff',
      fallbackRoleLabel: 'Inventory Staff',
      child: child,
    );
  }
}

/// Open stock alerts, the one live count on the stock manager's menu (ledger
/// ruling, F4): unresolved alerts at index 4 (Low stock). Read once when the
/// shell mounts; a failure shows no marker rather than a false 0.
Future<Map<int, int>> stockManagerMarkers() async {
  return {InventorySkeletonLayout.lowStockIndex: await unresolvedAlertsCount()};
}
