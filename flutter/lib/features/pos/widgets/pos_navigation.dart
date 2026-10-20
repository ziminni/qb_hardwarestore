import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Canonical POS sidebar items, in the append-only order from
/// planning/cashier-workflow/decisions/03-cashier-tab-set.md.
/// Phases 3 and 4 append items at the end; existing indices never renumber.
const List<DashboardNavigationItem> posNavigationItems = [
  DashboardNavigationItem('New transaction', Icons.point_of_sale_outlined),
  DashboardNavigationItem('Transaction history', Icons.receipt_long_outlined),
  DashboardNavigationItem('Release materials', Icons.inventory_2_outlined),
  DashboardNavigationItem('Record payment', Icons.payments_outlined),
];

/// Routes the POS shell sidebar tap to the matching page.
/// Same shape as `navigateInventory` / `navigateSales`.
void navigatePos(BuildContext context, int index) {
  final path = switch (index) {
    0 => AppRoutes.posDashboard,
    1 => AppRoutes.posHistory,
    2 => AppRoutes.posRelease,
    3 => AppRoutes.posReceivables,
    _ => null,
  };
  if (path != null) context.go(path);
}
