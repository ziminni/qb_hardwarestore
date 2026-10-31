// Card L1 (UI refresh): the login screen's controls must do what they say.
//
//  1. "Remember me" only ever set a local bool that nothing read, so the
//     username was gone after signing out. Decision D14: remember the USERNAME
//     only, with `shared_preferences`, never the password.
//  2. "Test server" is a developer tool that was shown in every build.
//     Decision D15: only when not `kReleaseMode`.
//  3. The card was the app's only `BackdropFilter` (a frosted glass panel):
//     costly on the web build and off-brand.
//  4. Sign-in errors were hand-built red text; they become the shared
//     `ErrorBanner`, and the server's own prose (wrong password, lockout) is
//     what it shows.

import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/token_store.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/views/login_page.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _usernameField = 'Enter your username or email';
const _passwordField = 'Enter your password';

void main() {
  setUp(() {
    // Preferences are per-test: the remember-me behaviour is a stored value.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // Tokens in memory: the real store is a platform plugin that never answers
    // under `flutter test`, which would leave the sign-in button spinning.
    ApiClient.instance.tokenStore = _MemoryTokenStore();
  });

  testWidgets('Remember me refills the username after signing out', (
    tester,
  ) async {
    final auth = AuthViewmodel(AuthRepository(_FakeAuthService()));
    await _pumpLogin(tester, auth);

    await _signIn(
      tester,
      identifier: 'cashier',
      password: 'demo1234',
      rememberMe: true,
    );
    expect(auth.isAuthenticated, isTrue, reason: 'the sign-in must succeed');

    await auth.logout();
    // The router shows a fresh login page after sign-out.
    await _pumpLogin(tester, auth, key: const ValueKey('after-sign-out'));

    expect(
      find.text('cashier'),
      findsOneWidget,
      reason: 'the remembered username is the point of the checkbox',
    );
  });

  testWidgets('an unticked Remember me leaves the next sign-in blank', (
    tester,
  ) async {
    final auth = AuthViewmodel(AuthRepository(_FakeAuthService()));
    await _pumpLogin(tester, auth);

    await _signIn(
      tester,
      identifier: 'cashier',
      password: 'demo1234',
      rememberMe: false,
    );
    await auth.logout();
    await _pumpLogin(tester, auth, key: const ValueKey('after-sign-out'));

    expect(find.text('cashier'), findsNothing);
  });

  testWidgets('the login card uses no blur filter', (tester) async {
    await _pumpLogin(tester, AuthViewmodel(AuthRepository(_FakeAuthService())));

    expect(
      find.byType(BackdropFilter),
      findsNothing,
      reason:
          'the frosted glass card was the app\'s only blur; the refresh '
          'drops it for the flat brand look',
    );
  });

  testWidgets('the server lockout message shows in the shared error banner', (
    tester,
  ) async {
    const lockout = 'Too many failed sign-in attempts. Try again in 5 minutes.';
    final auth = AuthViewmodel(
      AuthRepository(_FakeAuthService(loginError: lockout)),
    );
    await _pumpLogin(tester, auth);

    await _signIn(tester, identifier: 'cashier', password: 'wrong');

    expect(auth.error, lockout);
    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ErrorBanner),
        matching: find.text(lockout),
      ),
      findsOneWidget,
      reason: 'the server prose names the wait; it must survive untouched',
    );
  });
}

Future<void> _pumpLogin(
  WidgetTester tester,
  AuthViewmodel auth, {
  Key? key,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: auth,
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: LoginPage(key: key),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _signIn(
  WidgetTester tester, {
  required String identifier,
  required String password,
  bool rememberMe = false,
}) async {
  await tester.enterText(
    find.widgetWithText(TextFormField, _usernameField),
    identifier,
  );
  await tester.enterText(
    find.widgetWithText(TextFormField, _passwordField),
    password,
  );
  if (rememberMe) {
    await tester.tap(find.byType(Checkbox));
    await tester.pump();
  }
  await tester.tap(find.text('Sign in'));
  await tester.pumpAndSettle();
}

/// The two JWT keys, in memory, so `AuthRepository.login` finishes in a test.
class _MemoryTokenStore implements TokenStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// Answers like `POST /auth/login/` without a server: one account, or the
/// failure message a refusal would carry.
class _FakeAuthService extends AuthService {
  _FakeAuthService({this.loginError});

  final String? loginError;

  @override
  Future<AuthSession> login(String identifier, String password) async {
    if (loginError case final message?) throw AuthException(message);
    return const AuthSession(
      accessToken: 'access',
      refreshToken: 'refresh',
      user: User(
        id: 4,
        username: 'cashier',
        email: 'cashier@queenbuilders.local',
        fullName: 'Maria Santos',
        role: null,
      ),
    );
  }

  @override
  Future<void> logout() async {}
}
