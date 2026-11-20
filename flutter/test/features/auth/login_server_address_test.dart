// A phone build has no server address until someone types one, and it used to
// be settable only from the Bodega Profile - behind the login it was needed for.
// The phone login therefore offers "Server address" itself.

import 'package:client/core/config/api_config.dart';
import 'package:client/core/network/api_client.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/views/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() => ApiClient.instance.init());
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await ApiConfig.loadSaved();
  });

  testWidgets('the phone login sets the server address before signing in', (
    tester,
  ) async {
    await _pumpLogin(tester, showServerAddress: true);

    await tester.tap(find.byKey(const ValueKey('login-server-address')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('server-address-field')),
      '192.168.1.20:8000',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(ApiConfig.baseUrl, 'http://192.168.1.20:8000');
    expect(ApiClient.instance.dio.options.baseUrl, 'http://192.168.1.20:8000');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ApiConfig.savedKey), 'http://192.168.1.20:8000');
    // The login itself shows where it will sign in now.
    expect(find.textContaining('192.168.1.20:8000'), findsWidgets);
  });

  testWidgets('desktop and web logins do not show it', (tester) async {
    await _pumpLogin(tester, showServerAddress: false);

    expect(find.byKey(const ValueKey('login-server-address')), findsNothing);
  });
}

Future<void> _pumpLogin(
  WidgetTester tester, {
  required bool showServerAddress,
}) async {
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(_NoServerAuthService())),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: LoginPage(
          showTestServer: false,
          showServerAddress: showServerAddress,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _NoServerAuthService extends AuthService {
  @override
  Future<AuthSession> login(String identifier, String password) async {
    throw const AuthException('No server in this test.');
  }
}
