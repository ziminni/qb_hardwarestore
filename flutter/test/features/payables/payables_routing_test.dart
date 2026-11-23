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
    test('the inventory sidebar has no Payables entry (stock-focused)', () {
      final order = _areaOrder(AppAreas.inventory);
      expect(order, hasLength(16));
      expect(order, isNot(contains('inventoryPayables')));
    });

    test('the sales sidebar keeps 9 and gains Payables at 9', () {
      final order = _areaOrder(AppAreas.sales);
      expect(order, hasLength(14));
      expect(order[8], 'salesProjectRequests');
      expect(order[9], 'salesPayables');
      expect(
        order[10],
        'salesDeliveries',
        reason: 'F3 appends Deliveries BELOW Payables; neither index moves',
      );
      expect(order[11], 'salesTransfers');
      expect(order[12], 'salesSettings');
    });

    test('the Admin menu has no Payables', () {
      // Owner 2026-11-18: the Admin sees everything and acts on nothing; bills
      // show on the Dashboard's Finance tab.
      expect(
        AppDestinations.labelsFor(AppAreas.admin),
        isNot(contains('Payables')),
      );
    });
  });

  group('each payables page highlights its own entry', () {
    final source = _read('lib/features/payables/views/payables_page.dart');

    test('the inventory menu no longer lists Payables', () {
      final labels = AppDestinations.labelsFor(AppAreas.inventory);
      expect(labels, hasLength(16));
      expect(labels, isNot(contains('Payables')));
    });

    test('the sales shell declares 9', () {
      final sales = SalesSkeletonLayout.navigationSections
          .expand((section) => section.destinations)
          .toList();
      expect(sales[9].label, 'Payables');
      expect(sales[10].label, 'Deliveries');
      expect(source, contains('selectedNavigationIndex: 9'));
    });

    test('there is no admin shell and no admin route any more', () {
      expect(source, isNot(contains('AdminSkeletonLayout')));
      expect(
        _read('lib/routes/routes.dart'),
        isNot(contains('path: adminPayables')),
      );
    });
  });
}
