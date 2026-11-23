import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/features/inventory/widgets/inventory_navigation.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:flutter/material.dart';

/// The area a Reports page is drawn in.
///
/// Decision D-01: one report body, two shells — Store Manager (sales) and Stock
/// Manager (inventory). The body never chooses its own chrome; the route does,
/// and passes it down as this enum. The Admin has no Reports page (owner
/// 2026-11-18: the Admin sees everything and acts on nothing), so there is no
/// third shell here.
enum ReportsShell {
  sales(AppAreas.sales, 'Reports', 'Sales, VAT and stock reports for the store.'),
  inventory(
    AppAreas.inventory,
    'Reports',
    'Stock valuation, movements and requisitions.',
  );

  const ReportsShell(this.area, this.title, this.subtitle);

  final String area;
  final String title;
  final String subtitle;

  /// The route of this shell's catalogue home.
  String get cataloguePath => switch (this) {
    ReportsShell.sales => '/sales/reports/catalogue',
    ReportsShell.inventory => '/inventory/reports/catalogue',
  };

  /// The route of one report in this shell's shared viewer.
  String viewerPath(String reportId) => switch (this) {
    ReportsShell.sales => '/sales/reports/view/$reportId',
    ReportsShell.inventory => '/inventory/reports/view/$reportId',
  };
}

/// Wraps a Reports body in the shell of [shell], highlighting the sidebar's own
/// Reports row (the catalogue and every viewer are that tab's pages, so the
/// sidebar must not go blank while a report is open).
class ReportsShellScaffold extends StatelessWidget {
  const ReportsShellScaffold({
    super.key,
    required this.shell,
    required this.child,
  });

  final ReportsShell shell;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return switch (shell) {
      ReportsShell.sales => SalesSkeletonLayout(
        title: shell.title,
        subtitle: shell.subtitle,
        selectedNavigationIndex: AppDestinations.indexOf(
          'reports',
          AppAreas.sales,
        ),
        onNavigationSelected: (index) => navigateSales(context, index),
        child: child,
      ),
      ReportsShell.inventory => InventorySkeletonLayout(
        title: shell.title,
        subtitle: shell.subtitle,
        selectedNavigationIndex: AppDestinations.indexOf(
          'inventory.reports',
          AppAreas.inventory,
        ),
        onNavigationSelected: (index) => navigateInventory(context, index),
        child: child,
      ),
    };
  }
}
