// Phase 2 F3: a merged account works from the union of its areas.
//
// `redirectFor` receives the areas the server says the account holds. An
// account with ONE area keeps the Phase 4 rules exactly: that area is the whole
// assignment, an address outside its prefix bounces to its dashboard, and no
// picker is involved.
//
// An account with SEVERAL areas (decision 24) needs no pick at all: every
// prefix it holds opens, an `/admin` address it may use goes through the sales
// twin when it holds Sales but not Admin, and everything else lands on the
// combined dashboard. Unknown codes and duplicated assignments never count as
// several areas.

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

/// One address per area: the plainest route each prefix owns.
const _sampleRoutes = {
  'admin': AppRoutes.adminSettings,
  'sales': AppRoutes.salesTransactions,
  'inventory': AppRoutes.inventoryStock,
  'pos': AppRoutes.posHistory,
};

/// The three merged combinations this phase proves.
const _combos = [
  ['sales', 'pos'], // Store Manager + Cashier
  ['sales', 'inventory'], // Store Manager + Stock Manager
  ['admin', 'pos'], // Admin + Cashier
];

void main() {
  test('a merged account opens every prefix it holds', () {
    for (final combo in _combos) {
      for (final area in combo) {
        expect(
          _redirect(null, assigned: combo, location: _sampleRoutes[area]!),
          isNull,
          reason: 'holds $area: $combo may open ${_sampleRoutes[area]}',
        );
      }
    }
  });

  test('a merged account keeps every protected dashboard it holds', () {
    for (final combo in _combos) {
      for (final area in combo) {
        final dashboard = AppRoutes.dashboardForRole(area)!;
        expect(
          _redirect(null, assigned: combo, location: dashboard),
          isNull,
          reason: 'a held area dashboard stays reachable: $dashboard',
        );
      }
    }
  });

  test('a prefix the account does not hold goes to the combined landing', () {
    // Deliberately one case per missing prefix, plus a dashboard and a
    // deep-in-area address (the fence is the prefix, not the page).
    expect(
      _redirect(null, assigned: const ['sales', 'pos'], location: '/admin/x'),
      AppRoutes.combinedDashboard,
    );
    expect(
      _redirect(
        null,
        assigned: const ['sales', 'pos'],
        location: AppRoutes.inventoryDashboard,
      ),
      AppRoutes.combinedDashboard,
    );
    expect(
      _redirect(
        null,
        assigned: const ['sales', 'inventory'],
        location: AppRoutes.posHistory,
      ),
      AppRoutes.combinedDashboard,
    );
    expect(
      _redirect(
        null,
        assigned: const ['admin', 'pos'],
        location: AppRoutes.salesOrders,
      ),
      AppRoutes.combinedDashboard,
    );
    expect(
      _redirect(
        null,
        assigned: const ['admin', 'pos'],
        location: AppRoutes.inventoryLowStock,
      ),
      AppRoutes.combinedDashboard,
    );
  });

  test(
    'login, the picker and the unsupported screen hand over to the landing',
    () {
      for (final location in [
        AppRoutes.login,
        AppRoutes.areaPicker,
        AppRoutes.unsupportedRole,
      ]) {
        expect(
          _redirect(null, assigned: const ['sales', 'pos'], location: location),
          AppRoutes.combinedDashboard,
          reason:
              'no picker and no unsupported screen for a merged account: '
              '$location',
        );
      }
    },
  );

  test('the combined landing itself is the end of the redirect', () {
    expect(
      _redirect(
        null,
        assigned: const ['admin', 'pos'],
        location: AppRoutes.combinedDashboard,
      ),
      isNull,
      reason: 'redirecting the landing to itself would loop',
    );
  });

  test('an address outside the four prefixes is left to the router', () {
    for (final location in ['/cpms/jobs', '/site/whatever', '/']) {
      expect(
        _redirect(null, assigned: const ['admin', 'pos'], location: location),
        isNull,
        reason: 'an unknown address is not an area: $location',
      );
    }
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
    expect(
      _redirect(
        null,
        assigned: const ['inventory'],
        location: AppRoutes.inventoryStock,
      ),
      isNull,
      reason: 'a single area is its own active area',
    );
  });

  test(
    'a single-area account typing the combined landing stays on its own',
    () {
      for (final area in _sampleRoutes.keys) {
        expect(
          _redirect(
            null,
            assigned: [area],
            location: AppRoutes.combinedDashboard,
          ),
          AppRoutes.dashboardForRole(area),
          reason: 'a single-area account must never reach the merged landing',
        );
      }
    },
  );

  test('a revoked area turns a merged account back into a single one', () {
    // The same account loses Admin: what was an open admin address is now
    // outside its only area, and the picker never appears.
    expect(
      _redirect(
        null,
        assigned: const ['admin', 'pos'],
        location: AppRoutes.adminSettings,
      ),
      isNull,
    );
    expect(
      _redirect(
        null,
        assigned: const ['pos'],
        location: AppRoutes.adminSettings,
      ),
      AppRoutes.posDashboard,
    );
  });

  test('duplicate and unknown assignments are not several areas', () {
    expect(
      _redirect(
        null,
        assigned: const ['sales', 'sales'],
        location: AppRoutes.salesOrders,
      ),
      isNull,
      reason: 'the same area twice is one area, not a merged account',
    );
    expect(
      _redirect(
        null,
        assigned: const ['site_foreman'],
        location: AppRoutes.posHistory,
      ),
      AppRoutes.unsupportedRole,
      reason: 'an unknown code is no area at all',
    );
    expect(
      _redirect(
        null,
        assigned: const ['pos', 'site_foreman'],
        location: AppRoutes.salesOrders,
      ),
      AppRoutes.posDashboard,
      reason: 'one known area beside an unknown code is a single-area account',
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

  test('a single-area account keeps the picker address on its dashboard', () {
    expect(
      _redirect('pos', assigned: const ['pos'], location: AppRoutes.areaPicker),
      AppRoutes.posDashboard,
    );
  });

  test('the manager keeps the sales twin of an admin address', () {
    expect(
      _redirect(
        'sales',
        assigned: const ['sales'],
        location: AppRoutes.adminReports,
      ),
      AppRoutes.salesReports,
    );
  });

  test('a deep link survives for a merged account, prefix by prefix', () {
    expect(
      AppRoutes.splashDestination(
        isAuthenticated: true,
        role: null,
        from: AppRoutes.salesOrders,
        assignedAreas: const ['sales', 'pos'],
      ),
      AppRoutes.salesOrders,
      reason: 'a held prefix is the wanted page, not a landing',
    );
    expect(
      AppRoutes.splashDestination(
        isAuthenticated: true,
        role: null,
        from: AppRoutes.inventoryStock,
        assignedAreas: const ['sales', 'inventory'],
      ),
      AppRoutes.inventoryStock,
    );
    expect(
      AppRoutes.splashDestination(
        isAuthenticated: true,
        role: null,
        from: AppRoutes.adminSettings,
        assignedAreas: const ['admin', 'pos'],
      ),
      AppRoutes.adminSettings,
    );
  });

  test('a deep link into a blocked prefix redirects from the splash', () {
    expect(
      AppRoutes.splashDestination(
        isAuthenticated: true,
        role: null,
        from: AppRoutes.inventoryStock,
        assignedAreas: const ['sales', 'pos'],
      ),
      AppRoutes.combinedDashboard,
    );
    expect(
      AppRoutes.splashDestination(
        isAuthenticated: true,
        role: null,
        from: AppRoutes.adminSettings,
        assignedAreas: const ['sales', 'inventory'],
      ),
      AppRoutes.combinedDashboard,
    );
  });

  test('a merged account has no login, picker or unsupported address', () {
    for (final from in [
      null,
      '/',
      AppRoutes.login,
      AppRoutes.areaPicker,
      AppRoutes.unsupportedRole,
    ]) {
      expect(
        AppRoutes.splashDestination(
          isAuthenticated: true,
          role: null,
          from: from,
          assignedAreas: const ['sales', 'pos'],
        ),
        AppRoutes.combinedDashboard,
        reason: 'a merged account lands on the combined dashboard: $from',
      );
    }
  });

  test('unknown and unauthenticated deep links are unchanged', () {
    expect(
      AppRoutes.splashDestination(
        isAuthenticated: true,
        role: null,
        from: '/site/whatever',
        assignedAreas: const ['sales', 'pos'],
      ),
      '/site/whatever',
      reason: 'the router decides an address no area owns',
    );
    expect(
      AppRoutes.splashDestination(
        isAuthenticated: false,
        role: null,
        from: AppRoutes.salesOrders,
        assignedAreas: const ['sales', 'pos'],
      ),
      AppRoutes.login,
    );
  });

  test('a single-area deep link is untouched', () {
    expect(
      AppRoutes.splashDestination(
        isAuthenticated: true,
        role: 'sales',
        from: AppRoutes.salesOrders,
        assignedAreas: const ['sales'],
      ),
      AppRoutes.salesOrders,
    );
    expect(
      AppRoutes.splashDestination(
        isAuthenticated: true,
        role: 'sales',
        from: AppRoutes.posHeld,
        assignedAreas: const ['sales'],
      ),
      AppRoutes.salesDashboard,
    );
  });
}
