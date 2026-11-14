// Z2: a Store Manager who types an /admin/* address they may use lands on the
// same screen in the sales shell; an admin keeps the admin screen.

import 'package:client/routes/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each admin screen the manager may use has its sales twin', () {
    expect(
      AppRoutes.salesTwinOf(AppRoutes.adminReports),
      AppRoutes.salesReports,
    );
    expect(
      AppRoutes.salesTwinOf(AppRoutes.adminUserManagement),
      AppRoutes.salesStaff,
    );
    // Phase 1b (decisions 09/10/13): the same review queue, in the manager's
    // own shell, so answering a request never swaps their sidebar.
    expect(
      AppRoutes.salesTwinOf(AppRoutes.adminProjectRequests),
      AppRoutes.salesProjectRequests,
    );
  });

  // Decision 01: approvals moved to CPMS, so the admin queue is gone and the
  // manager typing /admin/requisitions bounces to their own dashboard instead
  // of landing on a twin that no longer exists.
  test('the retired approve queue has no twin', () {
    expect(AppRoutes.salesTwinOf('/admin/requisitions'), isNull);
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: 'sales',
        location: '/admin/requisitions',
      ),
      AppRoutes.salesDashboard,
    );
  });

  test('admin-only screens have no twin', () {
    for (final location in [
      AppRoutes.adminDashboard,
      AppRoutes.adminAuditLogs,
      AppRoutes.adminSettings,
      AppRoutes.adminInventory,
      AppRoutes.adminSales,
    ]) {
      expect(AppRoutes.salesTwinOf(location), isNull, reason: location);
    }
  });

  test('a merged account holding Sales and Cashier gets the twin', () {
    // F3 (decision 24): the union of the areas decides, not one active area.
    // This account holds Sales but not Admin, so every admin address with a
    // sales twin opens that twin instead of bouncing it to a dashboard.
    for (final adminRoute in [
      AppRoutes.adminReports,
      AppRoutes.adminUserManagement,
      AppRoutes.adminProjectRequests,
      AppRoutes.adminPayables,
      AppRoutes.adminDeliveries,
      AppRoutes.adminTransfers,
    ]) {
      expect(
        AppRoutes.redirectFor(
          isAuthenticated: true,
          role: null,
          location: adminRoute,
          assignedAreas: const ['sales', 'pos'],
        ),
        AppRoutes.salesTwinOf(adminRoute),
        reason: adminRoute,
      );
    }
    // An admin address with no twin is still fenced.
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: null,
        location: AppRoutes.adminAuditLogs,
        assignedAreas: const ['sales', 'pos'],
      ),
      AppRoutes.combinedDashboard,
    );
  });

  test('a merged account holding Admin opens the admin originals', () {
    // Admin + Cashier: the admin screens are its own, so nothing is twinned.
    for (final adminRoute in [
      AppRoutes.adminReports,
      AppRoutes.adminUserManagement,
      AppRoutes.adminSettings,
    ]) {
      expect(
        AppRoutes.redirectFor(
          isAuthenticated: true,
          role: null,
          location: adminRoute,
          assignedAreas: const ['admin', 'pos'],
        ),
        isNull,
        reason: adminRoute,
      );
    }
  });

  test('a merged account with no Sales and no Admin gets no twin', () {
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: null,
        location: AppRoutes.adminReports,
        assignedAreas: const ['inventory', 'pos'],
      ),
      AppRoutes.combinedDashboard,
    );
  });

  test('an admin still opens the admin screens', () {
    for (final location in [
      AppRoutes.adminReports,
      AppRoutes.adminUserManagement,
      AppRoutes.adminProjectRequests,
    ]) {
      expect(
        AppRoutes.redirectFor(
          isAuthenticated: true,
          role: 'admin',
          location: location,
        ),
        isNull,
        reason: location,
      );
    }
  });
}
