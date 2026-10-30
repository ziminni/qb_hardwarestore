import 'package:client/features/admin/viewmodels/admin_requisitions_viewmodel.dart';
import 'package:client/features/admin/views/requisitions_page.dart';
import 'package:flutter/material.dart';

/// The Store Manager's approval queue (sales sidebar index 7).
///
/// The manager is the requisition approver (decision 16), but the queue lived
/// only under /admin/ with the admin sidebar and no link from the manager's
/// screens. This is the same screen in the sales shell, as D-01 did for
/// Reports.
class SalesRequisitionsPage extends StatelessWidget {
  const SalesRequisitionsPage({super.key, this.viewmodel});

  /// Injected by tests; production lets the page own its viewmodel.
  final AdminRequisitionsViewmodel? viewmodel;

  @override
  Widget build(BuildContext context) =>
      RequisitionsPage(viewmodel: viewmodel, inSalesShell: true);
}
