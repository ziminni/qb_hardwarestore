import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:flutter/material.dart';

const List<DashboardNavigationItem> adminNavigationItems = [
  DashboardNavigationItem(
    'Overview',
    Icons.dashboard_outlined,
    route: '/admin/dashboard',
  ),
  DashboardNavigationItem(
    'User management',
    Icons.manage_accounts_outlined,
    route: '/admin/users',
  ),
  DashboardNavigationItem('Inventory', Icons.inventory_2_outlined),
  DashboardNavigationItem('Sales & POS', Icons.point_of_sale_outlined),
  DashboardNavigationItem('Requisitions', Icons.receipt_long_outlined),
  DashboardNavigationItem('Reports', Icons.bar_chart_rounded),
  DashboardNavigationItem('Audit logs', Icons.history_rounded),
  DashboardNavigationItem('Settings', Icons.settings_outlined),
];
