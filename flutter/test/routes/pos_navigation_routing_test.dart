// Decisions 02 + 04: POS-native pages /pos/history and /pos/receivables are
// reachable by the cashier and NOT fenced behind /sales/.

import 'package:client/routes/routes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('cashier reaches POS pages', () {
    for (final location in [
      AppRoutes.posDashboard,
      AppRoutes.posHistory,
      AppRoutes.posRelease,
      AppRoutes.posReceivables,
    ]) {
      test('pos stays on $location', () {
        expect(
          AppRoutes.redirectFor(
            isAuthenticated: true,
            role: 'pos',
            location: location,
          ),
          isNull,
        );
      });
    }
  });

  group('cashier is still bounced from other role areas', () {
    test('bounced from /sales/', () {
      expect(
        AppRoutes.redirectFor(
          isAuthenticated: true,
          role: 'pos',
          location: AppRoutes.salesTransactions,
        ),
        AppRoutes.posDashboard,
      );
    });

    test('bounced from /admin/', () {
      expect(
        AppRoutes.redirectFor(
          isAuthenticated: true,
          role: 'pos',
          location: '/admin/users',
        ),
        AppRoutes.posDashboard,
      );
    });

    test('bounced from /inventory/', () {
      expect(
        AppRoutes.redirectFor(
          isAuthenticated: true,
          role: 'pos',
          location: AppRoutes.inventoryDashboard,
        ),
        AppRoutes.posDashboard,
      );
    });
  });

  group('non-POS roles cannot sneak into protected POS dashboard', () {
    test('sales bounced from /pos/dashboard', () {
      expect(
        AppRoutes.redirectFor(
          isAuthenticated: true,
          role: 'sales',
          location: AppRoutes.posDashboard,
        ),
        AppRoutes.salesDashboard,
      );
    });
  });
}
