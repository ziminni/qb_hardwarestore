// Phase 5 F4 (decision 18): where the storage-locations screen lives.
//
// Three pins, because each one has silently broken in this project before:
//   * the route exists and is mounted in the router;
//   * it is APPENDED to the Admin sidebar below Deliveries, so no earlier index
//     moved (Payables 8 and Deliveries 9 keep their numbers);
//   * only an Admin opens it — every other area's typed address is sent to that
//     account's own dashboard by the `/admin/` prefix fence, which is the whole
//     fence for this screen because the server refuses writes for other roles.

import 'dart:io';

import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('the route exists and is mounted', () {
    test('the constant and its GoRoute are both there', () {
      final routes = _read('lib/routes/routes.dart');

      expect(AppRoutes.adminStorageLocations, '/admin/storage-locations');
      expect(routes, contains('path: adminStorageLocations'));
      expect(routes, contains('const StorageLocationsPage()'));
    });

    test('the page highlights its own appended sidebar index', () {
      // An index is just an int: 10 is as valid as 8, which is exactly how the
      // Task 19 regression got through.
      final page = _read(
        'lib/features/admin/views/storage_locations_page.dart',
      );
      expect(page, contains('selectedNavigationIndex: 10'));
    });
  });

  group('the Admin sidebar is append-only', () {
    test('earlier indices keep their numbers and errands', () {
      final groups = AdminSkeletonLayout.groups;
      final source = _read('lib/core/layout/admin_skeleton_layout.dart');
      final items = RegExp(
        r"\(\s*'([\w &]+)',\s*Icons[^)]*\),",
      ).allMatches(source).map((match) => match.group(1)!).toList();

      expect(AdminSkeletonLayout.projectRequestsIndex, 7);
      expect(groups[groups.length - 4], ('Projects', 7));
      expect(groups[groups.length - 3], ('Payables', 8));
      expect(groups[groups.length - 2], (
        'Deliveries',
        9,
      ), reason: 'F4 is appended BELOW the deliveries entry it must not move');
      expect(groups.last.$2, 10);
      expect(groups.last.$1, 'Locations');
      expect(items[10], 'Storage locations');
    });
  });

  group('redirectFor fences the screen to the Admin area', () {
    String? redirect(String role, String location) => AppRoutes.redirectFor(
      isAuthenticated: true,
      role: role,
      location: location,
      assignedAreas: [role],
    );

    test('a Cashier, Stock Manager or Store Manager typing the URL lands on '
        'their own dashboard', () {
      for (final (role, dashboard) in const [
        ('pos', AppRoutes.posDashboard),
        ('inventory', AppRoutes.inventoryDashboard),
        ('sales', AppRoutes.salesDashboard),
      ]) {
        expect(
          redirect(role, AppRoutes.adminStorageLocations),
          dashboard,
          reason:
              '$role reaches no storage-locations screen: the server answers '
              '403 to every write, so a readable page would be all failures',
        );
      }
    });

    test('an Admin stays', () {
      expect(redirect('admin', AppRoutes.adminStorageLocations), isNull);
    });
  });
}
