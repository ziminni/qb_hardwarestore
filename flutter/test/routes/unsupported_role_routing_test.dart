// Decision 04: every role in `apps/users/permissions.py` must resolve to either a
// dashboard or an explicit unsupported-role screen — never a silent loop to
// `/login`.
//
// The defect this replaces: `routes.dart` did
//     if (dashboard == null) return isLogin ? null : login;
// so an authenticated `site_foreman` (a CPMS-side identity with deliberately no
// POS dashboard) was bounced to `/login` and sat there while apparently signed
// in, with nothing telling them why.
//
// The role rules are tested through the **pure** `AppRoutes.redirectFor`, not by
// rendering a destination: every dashboard shares one skeleton whose existing
// layout assertions fire under a widget test, so a routing test that rendered a
// dashboard would fail for a reason unrelated to routing. The page itself is
// covered by rendering it directly, which is safe.

import 'package:client/app.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/views/login_page.dart';
import 'package:client/features/auth/views/unsupported_role_page.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// [redirectFor] with a signed-in actor, so each case states only what it varies.
String? _redirectFor(String? role, String location, {bool signedIn = true}) =>
    AppRoutes.redirectFor(
      isAuthenticated: signedIn,
      role: role,
      location: location,
    );

void main() {
  group('dashboardForRole (decision 04)', () {
    test('maps the four seeded roles that have a dashboard', () {
      expect(AppRoutes.dashboardForRole('admin'), AppRoutes.adminDashboard);
      expect(
        AppRoutes.dashboardForRole('inventory'),
        AppRoutes.inventoryDashboard,
      );
      expect(AppRoutes.dashboardForRole('pos'), AppRoutes.posDashboard);
      expect(AppRoutes.dashboardForRole('sales'), AppRoutes.salesDashboard);
    });

    test('gives site_foreman NO dashboard, deliberately', () {
      // Not an oversight: a Site Foreman is a CPMS-side identity. If this ever
      // gains a dashboard that is a product decision, not a bug fix.
      expect(AppRoutes.dashboardForRole('site_foreman'), isNull);
    });

    test('returns null for an unknown role and for a role-less account', () {
      expect(AppRoutes.dashboardForRole('something_new'), isNull);
      expect(AppRoutes.dashboardForRole(null), isNull);
    });
  });

  group('redirectFor — unmapped roles (the decision 04 fix)', () {
    test('an unmapped role at the login page goes to the unsupported screen', () {
      // The defect: this returned null and left them on a login form they had
      // already passed.
      expect(
        _redirectFor('site_foreman', AppRoutes.login),
        AppRoutes.unsupportedRole,
      );
    });

    test('a role-less account goes to the unsupported screen', () {
      expect(
        _redirectFor(null, AppRoutes.login),
        AppRoutes.unsupportedRole,
      );
    });

    test('an unknown role goes to the unsupported screen', () {
      expect(
        _redirectFor('something_new', AppRoutes.login),
        AppRoutes.unsupportedRole,
      );
    });

    test('an unmapped role is taken off a real screen too', () {
      expect(
        _redirectFor('site_foreman', AppRoutes.inventoryStock),
        AppRoutes.unsupportedRole,
      );
    });

    test('NO LOOP: an unmapped role already on the screen stays there', () {
      // This is the assertion that matters. If it returned anything but null the
      // router would redirect to itself forever.
      expect(_redirectFor('site_foreman', AppRoutes.unsupportedRole), isNull);
      expect(_redirectFor(null, AppRoutes.unsupportedRole), isNull);
    });

    test('a mapped role who lands on the unsupported screen is sent on', () {
      // Someone whose role is fixed in another tab should not be stranded.
      expect(
        _redirectFor('admin', AppRoutes.unsupportedRole),
        AppRoutes.adminDashboard,
      );
    });
  });

  group('redirectFor — the paths that must not regress', () {
    test('a signed-out user at the login page stays there', () {
      expect(_redirectFor(null, AppRoutes.login, signedIn: false), isNull);
    });

    test('a signed-out user anywhere else is sent to the login page', () {
      expect(
        _redirectFor(null, AppRoutes.inventoryStock, signedIn: false),
        AppRoutes.login,
      );
      expect(
        _redirectFor('admin', AppRoutes.adminDashboard, signedIn: false),
        AppRoutes.login,
      );
    });

    test('a mapped role at the login page reaches its dashboard', () {
      expect(_redirectFor('admin', AppRoutes.login), AppRoutes.adminDashboard);
      expect(
        _redirectFor('inventory', AppRoutes.login),
        AppRoutes.inventoryDashboard,
      );
      expect(_redirectFor('pos', AppRoutes.login), AppRoutes.posDashboard);
      expect(_redirectFor('sales', AppRoutes.login), AppRoutes.salesDashboard);
    });

    test('a role sitting on its own dashboard stays put', () {
      expect(_redirectFor('admin', AppRoutes.adminDashboard), isNull);
      expect(_redirectFor('pos', AppRoutes.posDashboard), isNull);
    });

    test('a role is kept out of another role\'s area', () {
      expect(
        _redirectFor('pos', AppRoutes.adminDashboard),
        AppRoutes.posDashboard,
      );
      expect(
        _redirectFor('inventory', AppRoutes.salesDashboard),
        AppRoutes.inventoryDashboard,
      );
      expect(
        _redirectFor('sales', AppRoutes.inventoryStock),
        AppRoutes.salesDashboard,
      );
    });
  });

  group('UnsupportedRolePage', () {
    Future<void> pump(WidgetTester tester, {String? role}) async {
      final auth = AuthViewmodel(AuthRepository(AuthService()));
      if (role != null) {
        auth.user = User(
          id: 1,
          username: role,
          email: '$role@example.com',
          fullName: 'Test $role',
          role: Role(id: 1, name: role, displayName: role),
          isActive: true,
        );
      }
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewmodel>.value(
          value: auth,
          child: const MaterialApp(home: UnsupportedRolePage()),
        ),
      );
      await tester.pump();
    }

    testWidgets('names the role so the user can act on it', (tester) async {
      await pump(tester, role: 'site_foreman');

      expect(find.textContaining('site_foreman'), findsWidgets);
    });

    testWidgets('explains a role-less account without naming a role', (
      tester,
    ) async {
      await pump(tester);

      expect(find.textContaining('no role assigned'), findsOneWidget);
      expect(find.textContaining('site_foreman'), findsNothing);
    });

    testWidgets('offers a way out', (tester) async {
      // Without an exit the user is stranded on a dead end while authenticated.
      await pump(tester, role: 'site_foreman');

      expect(find.text('Sign out'), findsOneWidget);
    });
  });

  group('router wiring', () {
    testWidgets('a signed-out launch still reaches the login page', (
      tester,
    ) async {
      final auth = AuthViewmodel(AuthRepository(AuthService()));

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewmodel>.value(
          value: auth,
          child: MyApp(auth: auth),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(UnsupportedRolePage), findsNothing);
    });

    testWidgets('an unmapped role reaches the unsupported screen end to end', (
      tester,
    ) async {
      // The real router, the real redirect: site_foreman must not be left on the
      // login page. The destination renders cleanly, unlike a dashboard.
      final auth = AuthViewmodel(AuthRepository(AuthService()))
        ..user = User(
          id: 1,
          username: 'foreman',
          email: 'foreman@example.com',
          fullName: 'Site Foreman',
          role: const Role(
            id: 5,
            name: 'site_foreman',
            displayName: 'Site Foreman',
          ),
          isActive: true,
        );

      await tester.pumpWidget(
        ChangeNotifierProvider<AuthViewmodel>.value(
          value: auth,
          child: MyApp(auth: auth),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(UnsupportedRolePage), findsOneWidget);
      expect(find.byType(LoginPage), findsNothing);
    });
  });
}
