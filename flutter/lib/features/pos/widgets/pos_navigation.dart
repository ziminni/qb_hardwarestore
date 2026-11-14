import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Canonical POS sidebar items, in the append-only order from
/// planning/cashier-workflow/decisions/03-cashier-tab-set.md, derived from
/// [AppDestinations] (Phase 2 F1). The menu is no longer written here: it is the
/// Till rows of the registry, and the index is a row's position.
final List<DashboardNavigationItem> posNavigationItems = [
  for (final destination in AppDestinations.forArea(AppAreas.pos))
    DashboardNavigationItem(destination.label, destination.icon),
];

/// Routes the POS shell sidebar tap to the matching page, from the registry.
/// Same shape as `navigateInventory` / `navigateSales`.
void navigatePos(BuildContext context, int index) {
  final path = AppDestinations.routeAt(AppAreas.pos, index);
  if (path != null) context.go(path);
}
