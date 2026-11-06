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

  test('an admin still opens the admin screens', () {
    for (final location in [
      AppRoutes.adminReports,
      AppRoutes.adminUserManagement,
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
