// Phase 1 QA (2026-11-07): an address that matches no route, such as a retired
// `/admin/requisitions` typed by an admin, showed GoRouter's debug page
// ("Page Not Found · GoException: no routes for location"). Any unmatched address
// now lands on the signed-in user's own dashboard, through the real router.

import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/routes/routes.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../support/phase4_fakes.dart';

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

void main() {
  testWidgets('an unknown address lands on the user\'s own dashboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    ApiClient.instance.init();
    ApiClient.instance.dio.httpClientAdapter = _OfflineAdapter();

    final auth = AuthViewmodel(AuthRepository(AuthService()))
      ..user = const User(
        id: 7,
        username: 'cashier',
        email: 'cashier@buildpro.ph',
        fullName: 'Ana Cruz',
        role: Role(id: 3, name: 'pos', displayName: 'Cashier'),
        isActive: true,
      );
    final router = AppRoutes.createRouter(auth);
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>.value(value: auth),
          ChangeNotifierProvider<InventoryViewmodel>(
            create: (_) => seededInventory(),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    router.go('/pos/not-a-screen');
    await tester.pumpAndSettle();

    expect(find.textContaining('GoException'), findsNothing);
    expect(find.textContaining('Page Not Found'), findsNothing);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      AppRoutes.posDashboard,
    );
  });
}
