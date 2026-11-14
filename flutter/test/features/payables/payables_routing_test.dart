// Phase 5 F2 (decision 18): where Payables lives, and who may open it.
//
// Three pins, because each one has silently broken before:
//   * the route exists in all three shells and each page highlights ITS OWN
//     sidebar entry (the Task 19 regression: an index is just an int);
//   * every payables path is APPENDED, so no earlier tab moved;
//   * a Cashier has no payables page at all — the area prefix fence sends a
//     typed address to that account's own dashboard, the way every other area
//     is fenced.

import 'dart:io';

import 'package:client/core/layout/admin_skeleton_layout.dart';
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
  group('redirectFor fences the payables routes', () {
    String? redirect(String role, String location) => AppRoutes.redirectFor(
      isAuthenticated: true,
      role: role,
      location: location,
      assignedAreas: [role],
    );

    test('a Cashier cannot open any payables page', () {
      for (final location in const [
        AppRoutes.inventoryPayables,
        AppRoutes.salesPayables,
        AppRoutes.adminPayables,
      ]) {
        expect(
          redirect('pos', location),
          AppRoutes.posDashboard,
          reason: '$location is not till work',
        );
      }
    });

    test('the Stock Manager opens the inventory one only', () {
      expect(redirect('inventory', AppRoutes.inventoryPayables), isNull);
      expect(
        redirect('inventory', AppRoutes.salesPayables),
        AppRoutes.inventoryDashboard,
      );
    });

    test('the Store Manager opens the sales one', () {
      expect(redirect('sales', AppRoutes.salesPayables), isNull);
    });

    test('an /admin address from the sales area lands on its sales twin', () {
      expect(
        redirect('sales', AppRoutes.adminPayables),
        AppRoutes.salesPayables,
        reason: 'same screen, own shell (the D-01 pattern)',
      );
    });

    test('the Admin opens the admin one', () {
      expect(redirect('admin', AppRoutes.adminPayables), isNull);
    });
  });

  group('every payables entry is APPENDED', () {
    test('the inventory sidebar keeps 13 and gains Payables at 13', () {
      final order = _indexRoutes(
        _read('lib/features/inventory/widgets/inventory_navigation.dart'),
      );
      expect(order, hasLength(16));
      expect(order[12], 'inventorySettings');
      expect(order[13], 'inventoryPayables');
      expect(
        order[14],
        'inventoryDeliveries',
        reason: 'F3 appends Deliveries BELOW Payables; neither index moves',
      );
      expect(
        order[15],
        'inventoryTransfers',
        reason: 'Phase 9 F3 appends Transfers last; no earlier index moves',
      );
    });

    test('the sales sidebar keeps 9 and gains Payables at 9', () {
      final nav = _read('lib/features/sales/widgets/sales_navigation.dart');
      final order = RegExp(
        r'AppRoutes\.(\w+),',
      ).allMatches(nav).map((match) => match.group(1)!).toList();
      expect(order, hasLength(12));
      expect(order[8], 'salesProjectRequests');
      expect(order[9], 'salesPayables');
      expect(
        order[10],
        'salesDeliveries',
        reason: 'F3 appends Deliveries BELOW Payables; neither index moves',
      );
      expect(order[11], 'salesTransfers');
    });

    test('the admin menu keeps 8 and gains Payables at 8', () {
      final layout = _read('lib/core/layout/admin_skeleton_layout.dart');
      final items = RegExp(
        r"\(\s*'(\w[^']*)',\s*Icons[^)]*\),",
      ).allMatches(layout).map((match) => match.group(1)!).toList();
      expect(items[7], 'Project requests');
      expect(items[8], 'Payables');
    });
  });

  group('each payables page highlights its own entry', () {
    final source = _read('lib/features/payables/views/payables_page.dart');

    test('the inventory shell declares 13', () {
      // The inventory layout keeps its menu private, so the labels are read from
      // its own source (the pattern `sidebar_index_consistency_test` uses).
      final layout = _read('lib/core/layout/inventory_skeleton_layout.dart');
      final labels = RegExp(
        r"SharedSidebarDestination\(\s*label: '([^']+)'",
      ).allMatches(layout).map((match) => match.group(1)!).toList();
      expect(labels, hasLength(16));
      expect(labels[12], 'Settings');
      expect(labels[13], 'Payables');
      expect(labels[14], 'Deliveries');
      expect(labels[15], 'Transfers');
      expect(source, contains('selectedNavigationIndex: 13'));
    });

    test('the sales shell declares 9', () {
      final sales = SalesSkeletonLayout.navigationSections
          .expand((section) => section.destinations)
          .toList();
      expect(sales[9].label, 'Payables');
      expect(sales[10].label, 'Deliveries');
      expect(source, contains('selectedNavigationIndex: 9'));
    });

    test('the admin shell declares 8', () {
      final admin = AdminSkeletonLayout.groups;
      final payables = admin.indexWhere((group) => group.$1 == 'Payables');
      expect(payables, isNot(-1), reason: 'the Payables group disappeared');
      expect(admin[payables].$2, 8);
      expect(source, contains('selectedNavigationIndex: 8'));
    });
  });
}
