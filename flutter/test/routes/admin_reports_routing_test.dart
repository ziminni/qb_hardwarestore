// Decision 16: the Store Manager is the month-end actor and IsManagerRole admits
// them server-side — the client fence must admit them to /admin/reports too.

import 'package:client/routes/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a store manager stays on the reports screen', () {
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: 'sales',
        location: AppRoutes.adminReports,
      ),
      isNull,
    );
  });

  test('a store manager still bounces off the other admin screens', () {
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: 'sales',
        location: '/admin/users',
      ),
      AppRoutes.salesDashboard,
    );
  });

  test('a cashier still bounces off the reports screen', () {
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: 'pos',
        location: AppRoutes.adminReports,
      ),
      AppRoutes.posDashboard,
    );
  });
}
