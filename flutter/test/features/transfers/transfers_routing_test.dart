// Phase 9 F3 (decision 21 §3): where Transfers lives, and who may open it.
//
// Pinned here, because each has silently broken before on this project:
//   * the route exists in all three shells that may move stock (Stock Manager,
//     Store Manager, Admin — `IsInventoryRole`) and a Cashier has none at all:
//     the server answers 403 to the list and to the write;
//   * every transfers entry is APPENDED (inventory 15, sales 11, admin after
//     Storage locations), so no earlier tab moved;
//   * each page declares the index of ITS OWN entry, not just a valid int.

import 'dart:io';

import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

/// The route CONSTANT NAMES of [area]'s menu, in flat index order.
///
/// Phase 2 F1 moved the menu into `AppDestinations`, so the order is read from
/// the registry the sidebar renders. Names are resolved from `routes.dart` so the
/// expectations below keep naming routes the way they always have.
List<String> _areaOrder(String area) {
  final names = {
    for (final match in RegExp(
      r"static const String (\w+) = '([^']+)';",
    ).allMatches(_read('lib/routes/routes.dart')))
      match.group(2)!: match.group(1)!,
  };
  return [for (final path in AppDestinations.routesFor(area)) names[path]!];
}

void main() {
  group('redirectFor fences the transfers routes', () {
    String? redirect(String role, String location) => AppRoutes.redirectFor(
      isAuthenticated: true,
      role: role,
      location: location,
      assignedAreas: [role],
    );

    test('a Cashier has no transfers page in any shell', () {
      for (final location in const [
        AppRoutes.inventoryTransfers,
        AppRoutes.salesTransfers,
        AppRoutes.adminTransfers,
      ]) {
        expect(
          redirect('pos', location),
          AppRoutes.posDashboard,
          reason: '$location moves stock, which the till may never do',
        );
      }
    });

    test('the Stock Manager opens the inventory one only', () {
      expect(redirect('inventory', AppRoutes.inventoryTransfers), isNull);
      expect(
        redirect('inventory', AppRoutes.salesTransfers),
        AppRoutes.inventoryDashboard,
      );
      expect(
        redirect('inventory', AppRoutes.adminTransfers),
        AppRoutes.inventoryDashboard,
      );
    });

    test('the Store Manager opens the sales one', () {
      expect(redirect('sales', AppRoutes.salesTransfers), isNull);
      expect(
        redirect('sales', AppRoutes.salesDeliveries),
        isNull,
        reason: 'an earlier appended tab still opens',
      );
    });

    test('an /admin address from the sales area lands on its sales twin', () {
      expect(
        redirect('sales', AppRoutes.adminTransfers),
        AppRoutes.salesTransfers,
        reason: 'same screen, own shell (the D-01 pattern)',
      );
    });

    test('the Admin opens the admin one', () {
      expect(redirect('admin', AppRoutes.adminTransfers), isNull);
    });
  });

  group('every transfers entry is APPENDED', () {
    test('the inventory sidebar has Transfers at 13 after Deliveries', () {
      final order = _areaOrder(AppAreas.inventory);
      expect(order, hasLength(16));
      expect(order[8], 'inventoryReceiving');
      expect(order[9], 'inventoryReturns');
      expect(order[12], 'inventoryDeliveries');
      expect(order[13], 'inventoryTransfers');
    });

    test('the sales sidebar gains Transfers at 11, moving nothing', () {
      final order = _areaOrder(AppAreas.sales);
      expect(order, hasLength(14));
      expect(order[6], 'salesReportCatalogue');
      expect(order[9], 'salesPayables');
      expect(order[10], 'salesDeliveries');
      expect(order[11], 'salesTransfers');
      expect(order[12], 'salesSettings');
    });

    test('the Admin menu has no Transfers and no admin route', () {
      // Owner 2026-11-18: the Admin sees everything and acts on nothing.
      expect(
        AppDestinations.labelsFor(AppAreas.admin),
        isNot(contains('Transfers')),
      );
      expect(
        _read('lib/routes/routes.dart'),
        isNot(contains('path: adminTransfers')),
      );
    });

    test('the inventory and sales layouts render the entry they advertise', () {
      final inventoryLabels = AppDestinations.labelsFor(AppAreas.inventory);
      expect(inventoryLabels, hasLength(16));
      expect(inventoryLabels[12], 'Deliveries');
      expect(inventoryLabels[13], 'Transfers');

      final salesLabels = SalesSkeletonLayout.navigationSections
          .expand((section) => section.destinations)
          .map((destination) => destination.label)
          .toList();
      expect(salesLabels, hasLength(14));
      expect(salesLabels[10], 'Deliveries');
      expect(salesLabels[11], 'Transfers');
      expect(salesLabels[12], 'Settings');

      expect(
        InventorySkeletonLayout.lowStockIndex,
        5,
        reason: 'the alert marker points at Low stock, which did not move',
      );
      expect(SalesSkeletonLayout.projectRequestsIndex, 8);
    });

    test('every transfers page declares its own shell index', () {
      final source = _read('lib/features/transfers/views/transfers_page.dart');
      final declared = RegExp(
        r'selectedNavigationIndex:\s*(\d+)',
      ).allMatches(source).map((match) => int.parse(match.group(1)!)).toList();
      expect(declared, containsAll(<int>[13, 11]));
      expect(declared, hasLength(2), reason: 'inventory and sales literal');
      expect(source, isNot(contains('AdminSkeletonLayout')));
    });
  });
}
