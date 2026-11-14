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

import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

List<String> _indexRoutes(String nav) {
  final pairs =
      RegExp(r'(\d+) => AppRoutes\.(\w+),')
          .allMatches(nav)
          .map((match) => MapEntry(int.parse(match.group(1)!), match.group(2)!))
          .toList()
        ..sort((a, b) => a.key.compareTo(b.key));
  return pairs.map((pair) => pair.value).toList();
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
    test('the inventory sidebar gains Transfers at 15, moving nothing', () {
      final order = _indexRoutes(
        _read('lib/features/inventory/widgets/inventory_navigation.dart'),
      );
      expect(order, hasLength(16));
      expect(order[8], 'inventoryReceiving');
      expect(order[13], 'inventoryPayables');
      expect(order[14], 'inventoryDeliveries');
      expect(order[15], 'inventoryTransfers');
    });

    test('the sales sidebar gains Transfers at 11, moving nothing', () {
      final order = RegExp(r'AppRoutes\.(\w+),')
          .allMatches(_read('lib/features/sales/widgets/sales_navigation.dart'))
          .map((match) => match.group(1)!)
          .toList();
      expect(order, hasLength(12));
      expect(order[6], 'salesReports');
      expect(order[9], 'salesPayables');
      expect(order[10], 'salesDeliveries');
      expect(order[11], 'salesTransfers');
    });

    test('the admin menu appends Transfers after Storage locations', () {
      final layout = _read('lib/core/layout/admin_skeleton_layout.dart');
      final items = RegExp(
        r"\(\s*'(\w[^']*)',\s*Icons",
      ).allMatches(layout).map((match) => match.group(1)!).toList();
      expect(items, hasLength(12));
      expect(items[7], 'Project requests');
      expect(items[8], 'Payables');
      expect(items[9], 'Deliveries');
      expect(
        items[10],
        'Storage locations',
        reason: 'the tab that was last keeps its index',
      );
      expect(items[11], 'Transfers');
      expect(AdminSkeletonLayout.groups.last, ('Transfers', 11));
    });

    test('the inventory and sales layouts render the entry they advertise', () {
      final inventoryLabels = RegExp(
        r"SharedSidebarDestination\(\s*label: '([^']+)'",
      ).allMatches(
        _read('lib/core/layout/inventory_skeleton_layout.dart'),
      ).map((match) => match.group(1)!).toList();
      expect(inventoryLabels, hasLength(16));
      expect(inventoryLabels[14], 'Deliveries');
      expect(inventoryLabels[15], 'Transfers');

      final salesLabels = SalesSkeletonLayout.navigationSections
          .expand((section) => section.destinations)
          .map((destination) => destination.label)
          .toList();
      expect(salesLabels, hasLength(12));
      expect(salesLabels[10], 'Deliveries');
      expect(salesLabels[11], 'Transfers');

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
      expect(declared, containsAll(<int>[15, 11]));
      expect(declared, hasLength(3), reason: 'one per shell');
    });
  });
}
