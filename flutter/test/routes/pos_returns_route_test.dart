// Phase 3 Task 4: the Returns tab must be REACHABLE through the real router.
//
// Why a route test and not just a page test: a page that renders when a test
// hands it its viewmodels proves nothing about whether the ROUTE provides what
// the page needs. AdminDashboard crashed exactly that way — the page was fine,
// the route forgot its provider, and the screen died with
// ProviderNotFoundException on first open.
//
// `/pos/returns` is a cashier route, so the redirect must let a `pos` account
// through; and the page builds its own viewmodels, so nothing above it needs a
// provider. Both are asserted here, against `AppRoutes.createRouter` — the same
// factory `MyApp` uses, not a hand-built lookalike.

import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/views/pos_returns_page.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:client/routes/routes.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// Answers every request the way an unreachable backend does: the page must
/// render its FAILURE state rather than throwing, which is what proves the route
/// wiring and not the network.
class _OfflineAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
      error: 'offline',
    );
  }

  @override
  void close({bool force = false}) {}
}

AuthViewmodel _cashier() => AuthViewmodel(AuthRepository(AuthService()))
  ..user = const User(
    id: 7,
    username: 'cashier',
    email: 'cashier@buildpro.ph',
    fullName: 'Ana Cruz',
    role: Role(id: 3, name: 'pos', displayName: 'Cashier'),
    isActive: true,
  );

void main() {
  test('the redirect lets a cashier stay on /pos/returns', () {
    expect(
      AppRoutes.redirectFor(
        isAuthenticated: true,
        role: 'pos',
        location: AppRoutes.posReturns,
      ),
      isNull,
    );
  });

  test('the POS dashboard stays fenced, so the till cannot be entered there', () {
    // `/pos/returns` itself sits under the same rule as every other POS subpage
    // (they are not individually fenced today — the POS *dashboard* is), so what
    // this pins is the existing rule and not a new one.
    for (final role in ['sales', 'inventory']) {
      expect(
        AppRoutes.redirectFor(
          isAuthenticated: true,
          role: role,
          location: AppRoutes.posDashboard,
        ),
        isNot(AppRoutes.posDashboard),
        reason: '$role must be bounced off the till dashboard',
      );
    }
  });

  testWidgets('the real router reaches the Returns page without a missing '
      'provider', (tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // `late final dio` is assigned once per process; the offline adapter makes
    // the shift load fail FAST and predictably instead of hanging on DNS.
    ApiClient.instance.init();
    ApiClient.instance.dio.httpClientAdapter = _OfflineAdapter();

    final auth = _cashier();
    final router = AppRoutes.createRouter(auth);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>.value(value: auth),
          // The cashier's LANDING page is the till, which reads these two from
          // the app-level MultiProvider `main.dart` sets up. Without them the
          // router dies on its first frame for a reason that has nothing to do
          // with the Returns tab.
          ChangeNotifierProvider<InventoryViewmodel>(
            create: (_) => InventoryViewmodel(),
          ),
          ChangeNotifierProvider<ProductTrackingViewmodel>(
            create: (_) => ProductTrackingViewmodel(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // A signed-in cashier lands on the till, not on the Returns tab.
    expect(find.byType(PosReturnsPage), findsNothing);

    router.go(AppRoutes.posReturns);
    await tester.pumpAndSettle();

    expect(
      find.byType(PosReturnsPage),
      findsOneWidget,
      reason:
          'the Returns tab must open through the real route, not only when a '
          'test constructs the page by hand',
    );
    // With the backend unreachable the shift check fails, and the page says so
    // instead of claiming there is no shift — the distinction the till makes.
    expect(find.text('The shift could not be checked.'), findsOneWidget);
  });
}
