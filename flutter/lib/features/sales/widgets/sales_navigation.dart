import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

void navigateSales(BuildContext context, int index) {
  final paths = [
    AppRoutes.salesDashboard,
    AppRoutes.salesTransactions,
    AppRoutes.salesQuotations,
    AppRoutes.salesOrders,
    AppRoutes.salesReceivables,
    AppRoutes.salesReturns,
    // Index 6 — Reports. Omitting it made the sidebar's Reports tab a silent
    // no-op: the index fell outside this list and nothing happened (D-01).
    AppRoutes.salesReports,
    // Index 7 - Staff, appended so no earlier index moves. Approvals used to sit
    // here and is gone (decision 01: CPMS approves). Same silent no-op risk as
    // D-01 if a path is missing here.
    AppRoutes.salesStaff,
    // Index 8 - Project requests, appended with its own sidebar section
    // (Phase 1b, decision 13). Same silent no-op risk as D-01 if the path is
    // missing here.
    AppRoutes.salesProjectRequests,
    // Index 9 - Payables, APPENDED with its own sidebar section (Phase 5 F2):
    // the Store Manager records supplier payments here, in their own shell.
    AppRoutes.salesPayables,
    // Index 10 - Deliveries, APPENDED (Phase 5 F3): the manager runs the
    // schedule from their own shell, so no earlier tab moves.
    AppRoutes.salesDeliveries,
    // Index 11 - Transfers, APPENDED (Phase 9 F3): the manager moves stock
    // between shelves in their own shell.
    AppRoutes.salesTransfers,
  ];
  if (index >= 0 && index < paths.length) context.go(paths[index]);
}
