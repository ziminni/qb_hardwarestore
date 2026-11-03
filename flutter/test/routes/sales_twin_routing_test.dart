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
      AppRoutes.salesTwinOf(AppRoutes.adminRequisitions),
      AppRoutes.salesRequisitions,
    );
    expect(
      AppRoutes.salesTwinOf(AppRoutes.adminUserManagement),
      AppRoutes.salesStaff,
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
      AppRoutes.adminRequisitions,
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
