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
  ];
  if (index >= 0 && index < paths.length) context.go(paths[index]);
}
