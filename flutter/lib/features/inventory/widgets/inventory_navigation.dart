import 'package:client/routes/routes.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

void navigateInventory(BuildContext context, int index) {
  final path = switch (index) {
    0 => AppRoutes.inventoryDashboard,
    1 => AppRoutes.inventoryProducts,
    2 => AppRoutes.inventoryCategories,
    3 => AppRoutes.inventoryStock,
    4 => AppRoutes.inventoryStockMovements,
    5 => AppRoutes.inventoryLowStock,
    6 => AppRoutes.inventoryPurchases,
    7 => AppRoutes.inventorySuppliers,
    8 => AppRoutes.inventorySales,
    9 => AppRoutes.inventoryReturns,
    10 => AppRoutes.inventoryReports,
    _ => null,
  };
  if (path != null) context.go(path);
}
