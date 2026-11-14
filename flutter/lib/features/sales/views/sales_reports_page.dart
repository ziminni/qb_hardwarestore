import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/features/admin/viewmodels/admin_reports_viewmodel.dart';
import 'package:client/features/admin/views/reports_page.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Store Manager's Reports tab (sales sidebar index 6, decision D-01).
///
/// It shows the SAME four tabs as the admin Reports screen — the body is
/// [ReportsContent], shared rather than copied — wrapped in the SALES shell, so
/// opening reports does not swap the manager's sidebar out from under them.
///
/// `ReportsPage` cannot be reused directly: it wraps itself in
/// `AdminSkeletonLayout`, which is exactly the shell this page exists to avoid.
class SalesReportsPage extends StatelessWidget {
  const SalesReportsPage({super.key, this.viewmodel});

  /// Injected by tests so the page renders without a server.
  ///
  /// The page otherwise builds its own viewmodel — same seam shape as
  /// [ReportsPage], which the state-sharing tests already rely on.
  final AdminReportsViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => (viewmodel ?? AdminReportsViewmodel())..load(),
      child: const _SalesReportsView(),
    );
  }
}

class _SalesReportsView extends StatelessWidget {
  const _SalesReportsView();

  @override
  Widget build(BuildContext context) {
    return SalesSkeletonLayout(
      title: 'Reports',
      subtitle: 'Managerial reports over live operations data.',
      selectedNavigationIndex: 6,
      onNavigationSelected: (index) => navigateSales(context, index),
      child: const ReportsContent(),
    );
  }
}
