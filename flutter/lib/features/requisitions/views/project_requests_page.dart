import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/features/requisitions/viewmodels/project_requests_viewmodel.dart';
import 'package:client/features/requisitions/widgets/project_requests_content.dart';
import 'package:client/features/sales/widgets/sales_navigation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// The Store Manager's "Requests from projects" queue (sales sidebar index 8).
///
/// ONE screen body ([ProjectRequestsContent]), two thin role shells: this one
/// and [AdminProjectRequestsPage]. Shells only so the manager keeps the sales
/// sidebar and the admin keeps the admin one (the D-01 pattern).
class ProjectRequestsPage extends StatelessWidget {
  const ProjectRequestsPage({super.key, this.viewmodel});

  /// Injected by tests so a state can be rendered WITHOUT a server.
  final ProjectRequestsViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => (viewmodel ?? ProjectRequestsViewmodel())..load(),
    child: const _ProjectRequestsView(inAdminShell: false),
  );
}

/// The same queue in the Admin shell (admin sidebar index 7).
class AdminProjectRequestsPage extends StatelessWidget {
  const AdminProjectRequestsPage({super.key, this.viewmodel});

  /// Injected by tests, as above.
  final ProjectRequestsViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
    create: (_) => (viewmodel ?? ProjectRequestsViewmodel())..load(),
    child: const _ProjectRequestsView(inAdminShell: true),
  );
}

class _ProjectRequestsView extends StatelessWidget {
  const _ProjectRequestsView({required this.inAdminShell});

  final bool inAdminShell;

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

    if (inAdminShell) {
      return AdminSkeletonLayout(
        title: title,
        subtitle: subtitle,
        selectedNavigationIndex: AdminSkeletonLayout.projectRequestsIndex,
        markers: _markers(viewmodel, AdminSkeletonLayout.projectRequestsIndex),
        // The list builds its rows lazily in an `Expanded`, so the body gets an
        // exact height instead of a page scroll view.
        scrollable: false,
        child: const ProjectRequestsContent(),
      );
    }

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
