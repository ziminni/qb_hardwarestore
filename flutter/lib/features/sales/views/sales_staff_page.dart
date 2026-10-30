import 'package:client/features/admin/viewmodels/admin_users_viewmodel.dart';
import 'package:client/features/admin/views/admin_user_management_page.dart';
import 'package:flutter/material.dart';

/// The Store Manager's staff list (sales sidebar index 8).
///
/// Phase 5 lets the manager offboard staff (decision 20), but the screen lived
/// only under /admin/ with the admin sidebar. This is the same screen in the
/// sales shell; what a manager may change is still decided inside it (only
/// an admin is offered Create account).
class SalesStaffPage extends StatelessWidget {
  const SalesStaffPage({super.key, this.viewmodel});

  /// Injected by tests; production lets the page own its viewmodel.
  final AdminUsersViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) =>
      AdminUserManagementPage(viewmodel: viewmodel, inSalesShell: true);
}
