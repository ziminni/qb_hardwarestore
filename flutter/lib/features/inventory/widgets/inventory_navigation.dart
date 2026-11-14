import 'package:client/routes/routes.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Maps a stocker sidebar destination index to its route and navigates there.
///
/// The index is the destination's POSITION in
/// `InventorySkeletonLayout._navigationSections` (SharedSidebar numbers
/// destinations across sections, 0-based, ignoring section headers). The two
/// lists are separate literals, so they can drift — they DID: Receiving sat on
/// index 9, which the sidebar renders as "Returns", so the Returns tab opened
/// the Receiving screen and Returns/Reports/Settings were unreachable.
///
/// `test/features/inventory/inventory_returns_routing_test.dart` now asserts this
/// order against the sidebar's own order, so the same drift fails a test.
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
    8 => AppRoutes.inventoryReceiving,
    9 => AppRoutes.inventorySales,
    10 => AppRoutes.inventoryReturns,
    11 => AppRoutes.inventoryReports,
    12 => AppRoutes.inventorySettings,
    // Index 13 - Payables, APPENDED with its own sidebar section (Phase 5 F2).
    13 => AppRoutes.inventoryPayables,
    // Index 14 - Deliveries, APPENDED (Phase 5 F3). The Stock Manager runs the
    // schedule, which is why the tab is in this shell.
    14 => AppRoutes.inventoryDeliveries,
    // Index 15 - Transfers, APPENDED (Phase 9 F3). The Stock Manager owns the
    // shelves, so the numbered moves between them are written from here.
    15 => AppRoutes.inventoryTransfers,
    _ => null,
  };
  if (path != null) context.go(path);
}
