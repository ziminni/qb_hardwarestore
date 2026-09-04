import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/dashboard/widget/pos_dashboard_content.dart';
import 'package:flutter/material.dart';

/// The point-of-sale dashboard page.
class POSDashboard extends StatelessWidget {
  const POSDashboard({super.key});

  @override
  Widget build(BuildContext context) {
    return const DashboardShell(
      title: 'POS Dashboard',
      subtitle: 'Low-fidelity mockup for the checkout workspace.',
      selectedNavigationIndex: 0,
      navigationItems: [
        DashboardNavigationItem(
          'New transaction',
          Icons.point_of_sale_outlined,
        ),
        DashboardNavigationItem(
          'Held transactions',
          Icons.pause_circle_outline,
        ),
        DashboardNavigationItem(
          'Transaction history',
          Icons.receipt_long_outlined,
        ),
        DashboardNavigationItem('Customers', Icons.people_outline),
        DashboardNavigationItem('End of shift', Icons.schedule_outlined),
      ],
      child: PosDashboardContent(),
    );
  }
}
