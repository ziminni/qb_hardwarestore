// Phase 5 F4 (decision 18): where the storage-locations screen lives.
//
// Owner 2026-11-18: it is a side tab of Admin → Settings now, not a menu row.
// Pinned here:
//   * the old address still exists and opens Settings on that tab, so links to
//     it (the dashboard's "switched off" row) keep working;
//   * the Admin menu has no Storage locations row;
//   * only an Admin opens it — every other area's typed address is sent to that
//     account's own dashboard by the `/admin/` prefix fence, which is the whole
//     fence for this screen because the server refuses writes for other roles.

import 'dart:io';

import 'package:client/core/constants/app_areas.dart';
import 'package:client/core/navigation/app_destinations.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('the old address opens Settings on its tab', () {
    test('the constant and its GoRoute are both there', () {
      final routes = _read('lib/routes/routes.dart');

      expect(AppRoutes.adminStorageLocations, '/admin/storage-locations');
      expect(routes, contains('path: adminStorageLocations'));
      expect(
        routes,
        contains('SettingsPage(initialSection: SettingsSection.locations)'),
      );
    });

    test('the Admin menu has no Storage locations row', () {
      expect(
        AppDestinations.labelsFor(AppAreas.admin),
        isNot(contains('Storage locations')),
      );
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
