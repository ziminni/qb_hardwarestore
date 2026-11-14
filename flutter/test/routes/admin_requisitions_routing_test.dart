// Decision 01 (locked 2026-11-03): the POS no longer approves requisitions.
// Requests are approved in CPMS, so /admin/requisitions and /sales/requisitions
// are RETIRED — no route, no sidebar entry, no sales twin.
//
// A typed old URL must behave exactly like any other address that matches no
// route: the fence decides first (a role outside the area goes to its own
// dashboard), and a role INSIDE the area is left alone; the router's onException
// then sends it to its own dashboard (test/routes/unknown_route_test.dart).

import 'dart:io';

import 'package:client/routes/routes.dart';
import 'package:flutter_test/flutter_test.dart';

const _retired = ['/admin/requisitions', '/sales/requisitions'];

String? _redirect(String role, String location) => AppRoutes.redirectFor(
  isAuthenticated: true,
  role: role,
  location: location,
);

void main() {
  for (final location in _retired) {
    group('$location is retired', () {
      test('the fence answers it exactly like an unknown address', () {
        for (final role in const ['admin', 'sales', 'pos', 'inventory']) {
          final unknown = location.replaceFirst(
            RegExp(r'/\w+$'),
            '/not-a-screen',
          );
          expect(
            _redirect(role, location),
            _redirect(role, unknown),
            reason:
                'a retired URL must not be special-cased: $role gets the same '
                'answer for $location and $unknown',
          );
        }
      });

      test('no role reaches a screen of its own on it', () {
        for (final role in const ['admin', 'sales', 'pos', 'inventory']) {
          expect(
            _redirect(role, location),
            isNot(anyOf(location, contains('requisition'))),
            reason: '$role must not land on a requisitions screen',
          );
        }
      });
    });
  }

  test('the store manager has no sales shell twin for the admin queue', () {
    expect(AppRoutes.salesTwinOf('/admin/requisitions'), isNull);
  });

  test('the routes file no longer registers either address', () {
    // Source-level, because the router keeps its route table private: a route
    // that survives in `routes.dart` is a screen a user can still open.
    final source = File('lib/routes/routes.dart').readAsStringSync();
    for (final location in _retired) {
      expect(source, isNot(contains("'$location'")), reason: location);
    }
    expect(source, isNot(contains('adminRequisitions')));
    expect(source, isNot(contains('salesRequisitions')));
  });
}
