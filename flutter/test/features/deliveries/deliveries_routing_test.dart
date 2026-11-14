// Phase 5 F3 (decision 18): where Deliveries lives, and who may open it.
//
// Three pins, because each has silently broken before:
//   * the route exists in all three shells and each page highlights ITS OWN
//     sidebar entry (an index is just an int);
//   * every deliveries path is APPENDED, so no earlier tab moved;
//   * a Cashier has no deliveries page at all — the server scopes a cashier to
//     their own slips but refuses every move with 403, so the read-only screen is
//     not offered (the sidebar stays exactly as it was).

import 'dart:io';

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
  group('redirectFor fences the deliveries routes', () {
    String? redirect(String role, String location) => AppRoutes.redirectFor(
      isAuthenticated: true,
      role: role,
      location: location,
      assignedAreas: [role],
    );

    test('a Cashier cannot open any deliveries page', () {
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
        final order = _indexRoutes(
          _read('lib/features/inventory/widgets/inventory_navigation.dart'),
        );
        expect(order, hasLength(16));
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
      final order = RegExp(r'AppRoutes\.(\w+),')
          .allMatches(_read('lib/features/sales/widgets/sales_navigation.dart'))
          .map((match) => match.group(1)!)
          .toList();
      expect(order, hasLength(12));
      expect(order[6], 'salesReports');
      expect(order[9], 'salesPayables');
      expect(order[10], 'salesDeliveries');
      expect(
        order[11],
        'salesTransfers',
        reason: 'Phase 9 F3 APPENDED Transfers at 11; nothing moved',
      );
    });

    test('every page declares its own shell index', () {
      final source = _read(
        'lib/features/deliveries/views/deliveries_page.dart',
      );
      final declared = RegExp(
        r'selectedNavigationIndex:\s*(\d+)',
      ).allMatches(source).map((match) => int.parse(match.group(1)!)).toList();
      expect(declared, containsAll(<int>[14, 10, 9]));
    });

    test('the admin menu appends Deliveries after Payables', () {
      final layout = _read('lib/core/layout/admin_skeleton_layout.dart');
      final items = RegExp(
        r"\(\s*'(\w[^']*)',\s*Icons",
      ).allMatches(layout).map((match) => match.group(1)!).toList();
      expect(items.indexOf('Payables'), 8);
      expect(items.indexOf('Deliveries'), 9);
    });
  });
}
