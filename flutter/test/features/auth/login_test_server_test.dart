// Card L1 (UI refresh): "Test server" is a developer tool (decision D15).
//
// It was a `FloatingActionButton` on every build of the login screen, in front
// of every user. It now renders only when `!kReleaseMode` (the production web
// build compiles the branch away), and [LoginPage.showTestServer] exists so a
// test can pump the release appearance, which a compile-time flag otherwise
// makes impossible.
//
// This file is separate from `login_page_test.dart` on purpose: its parameter
// does not exist on the old page, so it would turn that file's assertion
// failures into a compile error.

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
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  // The default is the build flag itself, so a developer build keeps the
  // control and a release build compiles it out. This test guards the wiring:
  // hardcoding the default to `false` (or to `kReleaseMode`, inverted) turns it
  // red. A literal `true` is only caught by a release-mode run.
  test('the default follows the build flag, not a literal', () {
    expect(const LoginPage().showTestServer, isTrue);
  });

  testWidgets('the release build has no "Test server" control', (tester) async {
    await _pumpLogin(tester, showTestServer: false);

    expect(find.text('Test server'), findsNothing);
  });

  testWidgets('a development build still offers "Test server"', (tester) async {
    await _pumpLogin(tester, showTestServer: true);

    expect(find.text('Test server'), findsOneWidget);
  });
}

Future<void> _pumpLogin(
  WidgetTester tester, {
  required bool showTestServer,
}) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(_NoServerAuthService())),
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: LoginPage(showTestServer: showTestServer),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// No request is made by these tests; the service is only a required argument.
class _NoServerAuthService extends AuthService {
  @override
  Future<AuthSession> login(String identifier, String password) async {
    throw const AuthException('No server in this test.');
  }
}
