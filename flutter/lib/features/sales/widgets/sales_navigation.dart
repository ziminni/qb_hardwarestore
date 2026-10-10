import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

void navigateSales(BuildContext context, int index) {
  final paths = [
    AppRoutes.salesDashboard,
    AppRoutes.salesTransactions,
    AppRoutes.salesQuotations,
    AppRoutes.salesOrders,
    AppRoutes.salesCustomers,
    AppRoutes.salesReceivables,
    AppRoutes.salesReturns,
    AppRoutes.salesReports,
  ];
  if (index >= 0 && index < paths.length) context.go(paths[index]);
}
