// Decision 20: the seeded Store Manager approves requisitions but the fence
// bounced them off /admin/requisitions — the queue admits role 'sales',
// mirroring the reports exemption. Nothing else under /admin/* opens.

import 'package:client/routes/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a store manager stays on the approve queue', () {
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: 'sales',
        location: AppRoutes.adminRequisitions,
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

  test('a cashier still bounces off the approve queue', () {
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: 'pos',
        location: AppRoutes.adminRequisitions,
      ),
      AppRoutes.posDashboard,
    );
  });
}
