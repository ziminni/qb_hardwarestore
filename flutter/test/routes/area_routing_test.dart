// Phase 4 F3b: the active AREA is UI state, the assignment is the authority.
//
// `redirectFor` receives the areas the server says the account holds. An
// account with several holds no active area until it picks one, so every
// location but the picker itself bounces there. A typed address outside the
// ACTIVE area redirects to that area's dashboard (never into another area's
// shell), and an account with no areas at all is the unsupported screen, not a
// dashboard.

import 'package:client/routes/routes.dart';
import 'package:flutter_test/flutter_test.dart';

String? _redirect(
  String? active, {
  List<String> assigned = const [],
  required String location,
  bool signedIn = true,
}) => AppRoutes.redirectFor(
  isAuthenticated: signedIn,
  role: active,
  location: location,
  assignedAreas: assigned,
);

void main() {
  test('several areas and no choice yet lands on the area picker', () {
    for (final location in [
      AppRoutes.posDashboard,
      AppRoutes.adminDashboard,
      AppRoutes.adminReports,
      AppRoutes.inventoryStock,
    ]) {
      expect(
        _redirect(null, assigned: const ['admin', 'pos'], location: location),
        AppRoutes.areaPicker,
        reason: 'nothing opens before an area is picked: $location',
      );
    }
  });

  test('the picker itself stays put while no area is chosen', () {
    expect(
      _redirect(
        null,
        assigned: const ['sales', 'inventory'],
        location: AppRoutes.areaPicker,
      ),
      isNull,
    );
  });

  test('an area chosen from the picker opens that area dashboard', () {
    expect(
      _redirect(
        'pos',
        assigned: const ['admin', 'pos'],
        location: AppRoutes.areaPicker,
      ),
      AppRoutes.posDashboard,
    );
    expect(
      _redirect(
        'pos',
        assigned: const ['admin', 'pos'],
        location: AppRoutes.posDashboard,
      ),
      isNull,
    );
  });

  test('the active area fences the other areas of the same account', () {
    // A multi-role cashier-admin working the till types an admin address: the
    // admin authority is real but the ACTIVE area is the till, so the address
    // redirects to the till dashboard instead of opening the admin shell.
    expect(
      _redirect(
        'pos',
        assigned: const ['admin', 'pos'],
        location: AppRoutes.adminSettings,
      ),
      AppRoutes.posDashboard,
    );
    expect(
      _redirect(
        'inventory',
        assigned: const ['inventory', 'sales'],
        location: AppRoutes.salesTransactions,
      ),
      AppRoutes.inventoryDashboard,
    );
  });

  test('the manager keeps the sales twin of an admin address', () {
    expect(
      _redirect(
        'sales',
        assigned: const ['sales', 'pos'],
        location: AppRoutes.adminReports,
      ),
      AppRoutes.salesReports,
    );
  });

  test('the cashier area is fenced like every other area', () {
    expect(
      _redirect(
        'admin',
        assigned: const ['admin', 'pos'],
        location: AppRoutes.posHistory,
      ),
      AppRoutes.adminDashboard,
    );
  });

  test('one area needs no picker and no stored choice', () {
    expect(
      _redirect(
        'pos',
        assigned: const ['pos'],
        location: AppRoutes.posDashboard,
      ),
      isNull,
    );
    expect(
      _redirect(
        'sales',
        assigned: const ['sales'],
        location: AppRoutes.posDashboard,
      ),
      AppRoutes.salesDashboard,
    );
  });

  test('an explicit empty roles list has no dashboard at all', () {
    expect(
      _redirect(null, assigned: const [], location: AppRoutes.login),
      AppRoutes.unsupportedRole,
      reason: 'a CPMS service account gets no POS screen',
    );
    expect(
      _redirect(null, assigned: const [], location: AppRoutes.unsupportedRole),
      isNull,
    );
    expect(
      _redirect(null, assigned: const [], location: AppRoutes.areaPicker),
      AppRoutes.unsupportedRole,
      reason: 'the picker is not a screen for an account with no areas',
    );
  });

  test('a released single-role call still behaves exactly as before', () {
    // No `assignedAreas`: the legacy `role` argument is the whole assignment.
    expect(_redirect('admin', location: AppRoutes.adminDashboard), isNull);
    expect(
      _redirect('admin', location: AppRoutes.posDashboard),
      AppRoutes.adminDashboard,
    );
    expect(
      _redirect(null, location: AppRoutes.login),
      AppRoutes.unsupportedRole,
    );
  });

  test('a deep link waits on the picker until an area is chosen', () {
    expect(
      AppRoutes.splashDestination(
        isAuthenticated: true,
        role: null,
        from: AppRoutes.adminReports,
        assignedAreas: const ['admin', 'sales'],
      ),
      AppRoutes.areaPicker,
    );
    expect(
      AppRoutes.splashDestination(
        isAuthenticated: true,
        role: 'admin',
        from: AppRoutes.adminReports,
        assignedAreas: const ['admin', 'sales'],
      ),
      AppRoutes.adminReports,
    );
  });
}
