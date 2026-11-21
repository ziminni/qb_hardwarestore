// Phase 5 F3 (decision 18): where Deliveries lives, and who may open it.
//
// Three pins, because each has silently broken before:
//   * the route exists in all three shells and each page highlights ITS OWN
//     sidebar entry (an index is just an int);
//   * every deliveries path is APPENDED, so no earlier tab moved;
//   * the Cashier has the TILL one — `/pos/deliveries`, APPENDED after Customers.
//     The server scopes a cashier to their own slips and admits exactly one move
//     on them (`start/`, direct sales only), so the till screen offers exactly
//     that; the other three shells keep the whole schedule and every move.

import 'dart:io';

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
  group('redirectFor fences the deliveries routes', () {
    String? redirect(String role, String location) => AppRoutes.redirectFor(
      isAuthenticated: true,
      role: role,
      location: location,
      assignedAreas: [role],
    );

    test('a Cashier cannot open the manager deliveries pages', () {
      for (final location in const [
        AppRoutes.inventoryDeliveries,
        AppRoutes.salesDeliveries,
        AppRoutes.adminDeliveries,
      ]) {
        expect(
          redirect('pos', location),
          AppRoutes.posDashboard,
          reason: '$location is not till work',
        );
      }
    });

    test('a Cashier opens the till own-dispatch page', () {
      expect(redirect('pos', AppRoutes.posDeliveries), isNull);
    });

    test('the Stock Manager opens the inventory one only', () {
      expect(redirect('inventory', AppRoutes.inventoryDeliveries), isNull);
      expect(
        redirect('inventory', AppRoutes.salesDeliveries),
        AppRoutes.inventoryDashboard,
      );
    });

    test('the Store Manager opens the sales one', () {
      expect(redirect('sales', AppRoutes.salesDeliveries), isNull);
    });

    test('an /admin address from the sales area lands on its sales twin', () {
      expect(
        redirect('sales', AppRoutes.adminDeliveries),
        AppRoutes.salesDeliveries,
        reason: 'same screen, own shell (the D-01 pattern)',
      );
    });

    test('the Admin opens the admin one', () {
      expect(redirect('admin', AppRoutes.adminDeliveries), isNull);
    });
  });

  group('every deliveries entry is APPENDED', () {
    test(
      'the inventory sidebar keeps 13 Payables and gains Deliveries at 14',
      () {
        final order = _areaOrder(AppAreas.inventory);
        expect(order, hasLength(17));
        expect(order[8], 'inventoryReceiving');
        expect(order[13], 'inventoryPayables');
        expect(order[14], 'inventoryDeliveries');
        expect(
          order[15],
          'inventoryTransfers',
          reason: 'Phase 9 F3 APPENDED Transfers at 15; nothing moved',
        );
      },
    );

    test('the sales sidebar keeps 9 Payables and gains Deliveries at 10', () {
      final order = _areaOrder(AppAreas.sales);
      expect(order, hasLength(13));
      expect(order[6], 'salesReports');
      expect(order[9], 'salesPayables');
      expect(order[10], 'salesDeliveries');
      expect(
        order[11],
        'salesTransfers',
        reason: 'Phase 9 F3 APPENDED Transfers at 11; nothing moved',
      );
      expect(order[12], 'salesSettings');
    });

    test('every page declares its own shell index', () {
      final source = _read(
        'lib/features/deliveries/views/deliveries_page.dart',
      );
      final declared = RegExp(
        r'selectedNavigationIndex:\s*(\d+)',
      ).allMatches(source).map((match) => int.parse(match.group(1)!)).toList();
      expect(declared, containsAll(<int>[14, 10]));
      // Owner 2026-11-18: no admin shell; the Admin only watches.
      expect(source, isNot(contains('AdminSkeletonLayout')));
    });

    test('the till sidebar keeps 8 Customers and gains Deliveries at 9', () {
      final order = _areaOrder(AppAreas.pos);
      expect(order, hasLength(10));
      expect(order[8], 'posCustomers');
      expect(order[9], 'posDeliveries');
    });

    test('the till page draws the till shell, not a manager one', () {
      final source = _read(
        'lib/features/deliveries/views/deliveries_page.dart',
      );
      expect(source, contains('selectedNavigationIndex: 9'));
      expect(source, contains('posNavigationItems'));
      expect(source, contains('class PosDeliveriesPage'));
    });

    test('the Admin menu has no Deliveries and no admin route', () {
      expect(
        AppDestinations.labelsFor(AppAreas.admin),
        isNot(contains('Deliveries')),
      );
      expect(
        _read('lib/routes/routes.dart'),
        isNot(contains('path: adminDeliveries')),
      );
    });
  });
}
