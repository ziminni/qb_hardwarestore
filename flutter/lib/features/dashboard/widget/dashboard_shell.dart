import 'package:client/data/services/held_cart_service.dart';
import 'package:client/shared/widgets/app_shell.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';

/// The POS (cashier) shell: the shared menu pattern inside [AppShell], grouped.
class DashboardShell extends StatelessWidget {
  const DashboardShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.selectedNavigationIndex,
    required this.navigationItems,
    required this.child,
    this.onNavigationSelected,
    this.scrollable = true,
    this.actions = const [],
    this.loadMarkers = cashierMarkers,
  });

  final String title;
  final String subtitle;
  final int selectedNavigationIndex;
  final List<DashboardNavigationItem> navigationItems;
  final Widget child;
  final ValueChanged<int>? onNavigationSelected;

  /// See [AppShell.scrollable].
  final bool scrollable;

  /// Widgets at the right end of the header (see [AppShell.actions]).
  final List<Widget> actions;

  /// See [AppShell.loadMarkers].
  final Future<Map<int, int>> Function() loadMarkers;

  /// Flat sidebar index of Held transactions, the destination the parked-cart
  /// count belongs to (0 New transaction, 1 Transaction history,
  /// 2 Release materials, 3 Record payment, 4 Held transactions). Shared by
  /// [cashierMarkers] and pinned by `sidebar_pattern_test.dart`.
  static const heldTransactionsIndex = 4;

  /// The cashier groups, by the index each item ALREADY has.
  ///
  /// `posNavigationItems` is append-only and its indexes are pinned by
  /// `sidebar_index_consistency_test.dart`, so a group is expressed as "where
  /// it starts". Grouping therefore cannot renumber a single destination.
  static const groups = [
    ('Selling', 0),
    ('Customers and projects', 2),
    ('Till', 4),
  ];

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      subtitle: subtitle,
      sections: _sectionsFor(navigationItems),
      selectedIndex: selectedNavigationIndex,
      onDestinationSelected: onNavigationSelected,
      scrollable: scrollable,
      actions: actions,
      loadMarkers: loadMarkers,
      child: child,
    );
  }

  static List<SharedSidebarSection> _sectionsFor(
    List<DashboardNavigationItem> items,
  ) {
    final sections = <SharedSidebarSection>[];
    for (var group = 0; group < groups.length; group++) {
      final start = groups[group].$2;
      if (start >= items.length) break;
      final nextStart = group + 1 < groups.length
          ? groups[group + 1].$2
          : items.length;
      final end = nextStart > items.length ? items.length : nextStart;
      sections.add(
        SharedSidebarSection(
          label: groups[group].$1,
          destinations: [
            for (final item in items.sublist(start, end))
              SharedSidebarDestination(label: item.label, icon: item.icon),
          ],
        ),
      );
    }
    return sections;
  }
}

class DashboardNavigationItem {
  const DashboardNavigationItem(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Parked baskets, the one live count on the cashier menu (ledger ruling, F4):
/// held transactions at index 4. Read once when the shell mounts; a failure
/// shows no marker rather than a false 0.
Future<Map<int, int>> cashierMarkers() async {
  final carts = await HeldCartService().fetchAll();
  return {DashboardShell.heldTransactionsIndex: carts.length};
}
