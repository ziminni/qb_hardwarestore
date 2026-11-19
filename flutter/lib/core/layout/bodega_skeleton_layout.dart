import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/shared/widgets/app_shell.dart';
import 'package:client/shared/widgets/shared_sidebar.dart';
import 'package:flutter/material.dart';

/// The Bodega Checker's shell (decision 25): Bodega stock, pick-ups and counts,
/// and nothing from the shop floor.
class BodegaSkeletonLayout extends StatelessWidget {
  const BodegaSkeletonLayout({
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
  final bool scrollable;

  /// Flat sidebar indexes, pinned by `bodega_navigation_test.dart`.
  static const int pickupsIndex = 0;
  static const int deliveriesIndex = 1;
  static const int stockIndex = 2;
  static const int historyIndex = 3;

  static List<SharedSidebarSection> get navigationSections =>
      AppDestinations.sectionsFor(AppAreas.bodega);

  @override
  Widget build(BuildContext context) {
    return AppShell(
      title: title,
      subtitle: subtitle,
      sections: navigationSections,
      selectedIndex: selectedNavigationIndex,
      originArea: AppAreas.bodega,
      onDestinationSelected: onNavigationSelected,
      scrollable: scrollable,
      fallbackUserName: 'Bodega Checker',
      fallbackRoleLabel: 'Bodega Checker',
      child: child,
    );
  }
}
