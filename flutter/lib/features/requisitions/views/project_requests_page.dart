import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/features/requisitions/viewmodels/project_requests_viewmodel.dart';
import 'package:client/features/requisitions/widgets/project_requests_content.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Store Manager's "Requests from projects" queue (sales sidebar index 8).
///
/// ONE screen body ([ProjectRequestsContent]). The Admin shell's copy was
/// removed with its menu row (owner 2026-11-18): the queue is the Store
/// Manager's.
class ProjectRequestsPage extends StatelessWidget {
  const ProjectRequestsPage({super.key, this.viewmodel});

  /// Injected by tests so a state can be rendered WITHOUT a server.
  final ProjectRequestsViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    // Kept fresh while open: a request CPMS sends appears without re-login.
    create: (_) => (viewmodel ?? ProjectRequestsViewmodel())
      ..load()
      ..startAutoRefresh(),
    child: const _ProjectRequestsView(),
  );
}

class _ProjectRequestsView extends StatelessWidget {
  const _ProjectRequestsView();

  /// The badge is THIS page's own count, read by the viewmodel's separate
  /// `waitingCount`, so a decision taken here updates it immediately. An
  /// unconfirmed count (null) passes no marker at all: a missing count is never
  /// drawn as 0, and a real 0 is passed through so the badge clears.
  static Map<int, int> _markers(ProjectRequestsViewmodel viewmodel, int index) {
    final count = viewmodel.waitingCount;
    return count == null ? const {} : {index: count};
  }

  @override
  Widget build(BuildContext context) {
    final viewmodel = context.watch<ProjectRequestsViewmodel>();
    const title = 'Requests from projects';
    const subtitle = 'Project material requests waiting for the store.';

    return SalesSkeletonLayout(
      title: title,
      subtitle: subtitle,
      selectedNavigationIndex: SalesSkeletonLayout.projectRequestsIndex,
      markers: _markers(viewmodel, SalesSkeletonLayout.projectRequestsIndex),
      onNavigationSelected: (index) => navigateSales(context, index),
      scrollable: false,
      child: const ProjectRequestsContent(),
    );
  }
}
