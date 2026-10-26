// Phase 5 Task 2: the Store Manager offboards staff in-app, so the client
// fence admits them to /admin/users like /admin/reports and /admin/requisitions.
// Admin-only screens (audit logs, settings) still bounce them.

import 'package:client/routes/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a store manager stays on the user management screen', () {
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: 'sales',
        location: AppRoutes.adminUserManagement,
      ),
      isNull,
    );
  });

  test('a store manager still bounces off audit logs and settings', () {
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: 'sales',
        location: AppRoutes.adminAuditLogs,
      ),
      AppRoutes.salesDashboard,
    );
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: 'sales',
        location: AppRoutes.adminSettings,
      ),
      AppRoutes.salesDashboard,
    );
  });

  test('a cashier still bounces off user management', () {
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: 'pos',
        location: AppRoutes.adminUserManagement,
      ),
      AppRoutes.posDashboard,
    );
  });
}
