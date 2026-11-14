// Smoke test for the app's unauthenticated entry path.
//
// Replaces Flutter's default counter template, which could never compile against
// this app: it imported `package:client/main.dart` and called `const MyApp()`,
// but `MyApp` lives in `package:client/app.dart` and requires an `auth` argument.
// That compile error blocked `flutter test` entirely.
//
// Since the splash screen is the router's initial location (card SYNC), the
// launch path is splash then login, and this is also the one test that proves
// `MyApp` still puts the login-to-dashboard hand-off in `MaterialApp.builder`.

import 'package:client/app.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/views/login_page.dart';
import 'package:client/features/auth/widget/login_transition_overlay.dart';
import 'package:client/features/splash/views/splash_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('launching without a session shows the splash, then login', (
    WidgetTester tester,
  ) async {
    final auth = AuthViewmodel(_NoSessionRepository());

    // Mirrors main.dart, which supplies AuthViewmodel above MyApp and no
    // longer waits for the restore: the splash does that.
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthViewmodel>.value(
        value: auth,
        child: MyApp(auth: auth),
      ),
    );
    await tester.pump();

    expect(
      find.byType(SplashPage),
      findsOneWidget,
      reason: 'the branded intro is the first frame now',
    );

    await tester.pump(SplashPage.introDuration);
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(
      find.byType(LoginTransitionOverlay),
      findsOneWidget,
      reason: 'the hand-off lives above every route, in MaterialApp.builder',
    );
  });
}

/// No saved session: secure storage answers "nothing here".
class _NoSessionRepository extends AuthRepository {
  _NoSessionRepository() : super(_FakeAuthService());

  @override
  Future<User?> restoreSession() async => null;
}

class _FakeAuthService extends AuthService {
  @override
  Future<AuthSession> login(String identifier, String password) async {
    throw const AuthException('not used in this test');
  }

  @override
  Future<void> logout() async {}
}
