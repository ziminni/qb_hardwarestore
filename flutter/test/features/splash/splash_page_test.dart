// Card SYNC (P2): the splash screen must never be a dead end.
//
// The teammate's version plays a 2.4 s intro while the saved session restores,
// then sends everyone to `/login` and lets the router sort the role out. That
// drops a DEEP LINK: the app opened at `/inventory/low-stock` restores the
// session, lands on `/login`, and the role rules send the stock manager to the
// dashboard instead of the page they asked for. It also never checked
// `MediaQuery.disableAnimations` (only the platform accessibility flag), and a
// throwing restore would have left it spinning.
//
// The router is driven for real here (`AppRoutes.redirectFor`, `splashFrom`,
// `splashDestination`), with stub target pages: our dashboards are built on a
// shared skeleton whose own layout assertions fire under a widget test, which
// would make a routing failure look like a layout failure.

import 'dart:async';

import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/splash/views/splash_page.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

void main() {
  group(
    'the redirect parks a deep link on the splash until the session loads',
    () {
      test('a deep link is carried, not dropped', () {
        expect(
          AppRoutes.redirectFor(
            isAuthenticated: false,
            role: null,
            location: AppRoutes.inventoryLowStock,
            isInitializing: true,
          ),
          AppRoutes.splashFrom(AppRoutes.inventoryLowStock),
        );
      });

      test('the splash itself is left alone while it animates', () {
        expect(
          AppRoutes.redirectFor(
            isAuthenticated: false,
            role: null,
            location: AppRoutes.splash,
            isInitializing: true,
          ),
          isNull,
        );
        expect(
          AppRoutes.redirectFor(
            isAuthenticated: false,
            role: null,
            location: AppRoutes.splash,
          ),
          isNull,
        );
      });

      test('after the restore the role rules decide, deep link first', () {
        // The stock manager keeps the page they asked for.
        expect(
          AppRoutes.splashDestination(
            isAuthenticated: true,
            role: 'inventory',
            from: AppRoutes.inventoryLowStock,
          ),
          AppRoutes.inventoryLowStock,
        );
        // Another role is bounced to its own dashboard by the existing rules.
        expect(
          AppRoutes.splashDestination(
            isAuthenticated: true,
            role: 'pos',
            from: AppRoutes.inventoryLowStock,
          ),
          AppRoutes.posDashboard,
        );
        // No `from` at all: login, which the router turns into the dashboard.
        expect(
          AppRoutes.splashDestination(isAuthenticated: true, role: 'admin'),
          AppRoutes.adminDashboard,
        );
        expect(
          AppRoutes.splashDestination(isAuthenticated: false, role: null),
          AppRoutes.login,
        );
        // A groupless account still gets the explicit screen (decision 04).
        expect(
          AppRoutes.splashDestination(isAuthenticated: true, role: null),
          AppRoutes.unsupportedRole,
        );
      });
    },
  );

  group('the splash screen hands over to the router', () {
    testWidgets('a signed-out start lands on the login screen', (tester) async {
      await _pumpSplash(tester, _FakeRepository());
      await tester.pumpAndSettle();

      expect(find.text(_login), findsOneWidget);
    });

    testWidgets('a restored session lands on that role\'s dashboard', (
      tester,
    ) async {
      await _pumpSplash(tester, _FakeRepository(role: 'admin', restore: true));
      await tester.pumpAndSettle();

      expect(find.text(_adminDashboard), findsOneWidget);
    });

    testWidgets('a role-less account lands on the unsupported screen', (
      tester,
    ) async {
      await _pumpSplash(tester, _FakeRepository(restore: true));
      await tester.pumpAndSettle();

      expect(
        find.text(_unsupported),
        findsOneWidget,
        reason: 'a groupless account gets the explicit screen (decision 04)',
      );
    });

    testWidgets('a deep link with a remembered session lands on that page', (
      tester,
    ) async {
      // The platform hands the app `/inventory/low-stock` directly, so the
      // redirect has to park it on the splash itself; that is the gate the
      // pure test above pins.
      await _pumpSplash(
        tester,
        _FakeRepository(role: 'inventory', restore: true),
        initialLocation: AppRoutes.inventoryLowStock,
      );
      await tester.pumpAndSettle();

      expect(
        find.text(_lowStockPage),
        findsOneWidget,
        reason: 'the deep link must survive the session restore',
      );
      expect(find.text(_login), findsNothing);
    });

    testWidgets('a failing restore falls back to the login screen', (
      tester,
    ) async {
      await _pumpSplash(tester, _FakeRepository(throwsOnRestore: true));
      await tester.pumpAndSettle();

      expect(
        find.text(_login),
        findsOneWidget,
        reason: 'the splash must never wait on a failed restore forever',
      );
    });

    testWidgets('a restore that never answers reaches the login form', (
      tester,
    ) async {
      // FX1: secure storage or `/auth/me/` can hang. The splash bounds the wait
      // at 10 s; if `isInitializing` stays true the redirect parks `/login`
      // back on `/splash?from=/login`, so the timeout lands nowhere.
      final gate = Completer<User?>();
      await _pumpSplash(tester, _FakeRepository(restoreGate: gate));
      await tester.pump();
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();

      expect(
        find.text(_login),
        findsOneWidget,
        reason: 'the timeout must reach the form, not bounce back to splash',
      );

      // The restore answers late. Nobody may be signed in behind the form, and
      // the route must not move under a user who is now typing credentials.
      gate.complete(
        User(
          id: 5,
          username: 'staff',
          email: 'staff@queenbuilders.local',
          fullName: 'Ana Reyes',
          role: Role(id: 1, name: 'admin', displayName: 'Admin'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(_login), findsOneWidget);
      expect(find.text(_adminDashboard), findsNothing);
    });

    testWidgets('reduced motion skips the intro animation', (tester) async {
      await _pumpSplash(tester, _FakeRepository(), reduceMotion: true);
      // Two frames: the restore already answered, so a skipped animation
      // hands over at once instead of unfolding over 1.4 s.
      await tester.pump();
      await tester.pump();

      expect(find.text(_login), findsOneWidget);
    });

    testWidgets('without reduced motion the intro is still on screen', (
      tester,
    ) async {
      await _pumpSplash(tester, _FakeRepository());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));

      expect(find.byType(SplashPage), findsOneWidget);
      expect(find.text(_login), findsNothing);
    });
  });
}

const _login = 'login screen';
const _adminDashboard = 'admin dashboard';
const _lowStockPage = 'low stock page';
const _unsupported = 'unsupported screen';

/// Pumps the real splash page inside a router wired with the SAME redirect
/// functions `AppRoutes.createRouter` uses, with stub pages for the targets.
Future<void> _pumpSplash(
  WidgetTester tester,
  AuthRepository repository, {
  String initialLocation = AppRoutes.splash,
  bool reduceMotion = false,
}) async {
  final auth = AuthViewmodel(repository);
  final router = GoRouter(
    initialLocation: initialLocation,
    refreshListenable: auth,
    redirect: (context, state) => AppRoutes.redirectFor(
      isAuthenticated: auth.isAuthenticated,
      role: auth.roleName,
      location: state.matchedLocation,
      isInitializing: auth.isInitializing,
    ),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashPage(),
      ),
      for (final (path, label) in const [
        (AppRoutes.login, _login),
        (AppRoutes.adminDashboard, _adminDashboard),
        (AppRoutes.unsupportedRole, _unsupported),
        (AppRoutes.inventoryLowStock, _lowStockPage),
        (AppRoutes.posDashboard, 'pos dashboard'),
        (AppRoutes.inventoryDashboard, 'inventory dashboard'),
        (AppRoutes.salesDashboard, 'sales dashboard'),
      ])
        GoRoute(path: path, builder: (context, state) => Text(label)),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: auth,
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  );
}

/// Restores the saved session (or fails like secure storage does, or hangs).
class _FakeRepository extends AuthRepository {
  _FakeRepository({
    this.role,
    this.restore = false,
    this.throwsOnRestore,
    this.restoreGate,
  }) : super(_FakeAuthService());

  final String? role;

  /// Whether a saved session exists at all (a role-less one still counts).
  final bool restore;
  final bool? throwsOnRestore;

  /// A restore that only answers when the test completes it.
  final Completer<User?>? restoreGate;

  /// Marks the gate complete if the test ends without answering it.
  @override
  Future<User?> restoreSession() async {
    if (restoreGate != null) return restoreGate!.future;
    if (throwsOnRestore ?? false) {
      throw StateError('secure storage unavailable');
    }
    if (!restore) return null;
    return User(
      id: 5,
      username: 'staff',
      email: 'staff@queenbuilders.local',
      fullName: 'Ana Reyes',
      role: role == null ? null : Role(id: 4, name: role!, displayName: role!),
    );
  }
}

class _FakeAuthService extends AuthService {
  @override
  Future<AuthSession> login(String identifier, String password) async {
    throw const AuthException('not used in these tests');
  }

  @override
  Future<void> logout() async {}
}
