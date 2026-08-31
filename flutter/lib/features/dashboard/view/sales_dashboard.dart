import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/dashboard/widget/sales_dashboard_content.dart';
import 'package:flutter/material.dart';

class SalesDashboard extends StatelessWidget {
  const SalesDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const DashboardShell(
      title: 'Sales Dashboard',
      subtitle: 'Low-fidelity mockup for sales monitoring and reports.',
      selectedNavigationIndex: 0,
      navigationItems: [
        DashboardNavigationItem('Overview', Icons.dashboard_outlined),
        DashboardNavigationItem('Transactions', Icons.receipt_long_outlined),
        DashboardNavigationItem('Customers', Icons.people_outline),
        DashboardNavigationItem(
          'Collections',
          Icons.account_balance_wallet_outlined,
        ),
        DashboardNavigationItem('Reports', Icons.bar_chart_outlined),
      ],
      child: SalesDashboardContent(),
    );
  }
}
