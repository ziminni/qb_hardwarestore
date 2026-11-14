// Card SYNC (P3): the branded hand-off between the login form and the
// dashboard must not cost the user anything it does not show.
//
// Three things the design has to get right, and each has a test below: it plays
// only on a SUCCESSFUL sign-in, it gives input back the moment it finishes, and
// it does not play at all under reduced motion.

import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/widget/login_transition_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets(
    'a successful sign-in plays the hand-off, then hands input back',
    (tester) async {
      var buttonTaps = 0;
      final auth = AuthViewmodel(_FakeRepository());
      await _pump(tester, auth, onTap: () => buttonTaps++);

      // What the login form does on success.
      await auth.login('cashier', 'demo1234');
      await tester.pump();
      // A third of the way in: the welcome copy has faded up.
      await tester.pump(const Duration(milliseconds: 900));

      expect(find.text('WELCOME BACK'), findsOneWidget);

      await tester.tap(find.text('underneath'));
      expect(
        buttonTaps,
        0,
        reason:
            'the overlay covers the screen, so the dashboard is not live yet',
      );

      // Past the end of the intro: the layer leaves the tree.
      await tester.pump(LoginTransitionOverlay.duration);
      await tester.pump();
      expect(find.text('WELCOME BACK'), findsNothing);

      await tester.tap(find.text('underneath'));
      expect(buttonTaps, 1, reason: 'the dashboard must be interactive again');
    },
  );

  testWidgets('a failed sign-in plays nothing', (tester) async {
    final auth = AuthViewmodel(_FakeRepository(loginError: 'Wrong password.'));
    await _pump(tester, auth);

    await auth.login('cashier', 'wrong');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('WELCOME BACK'), findsNothing);
    expect(auth.error, 'Wrong password.');
  });

  testWidgets('reduced motion skips the hand-off entirely', (tester) async {
    var buttonTaps = 0;
    final auth = AuthViewmodel(_FakeRepository());
    await _pump(tester, auth, reduceMotion: true, onTap: () => buttonTaps++);

    await auth.login('cashier', 'demo1234');
    await tester.pump();
    // The same point in time at which the animated hand-off is showing its
    // welcome copy: under reduced motion nothing may be covering the screen.
    await tester.pump(const Duration(milliseconds: 900));

    expect(find.text('WELCOME BACK'), findsNothing);
    await tester.tap(find.text('underneath'));
    expect(buttonTaps, 1, reason: 'the dashboard is live from the first frame');
  });
}

/// The overlay in `MaterialApp.builder`, the only place it ever lives, over a
/// tappable child that stands in for the dashboard.
Future<void> _pump(
  WidgetTester tester,
  AuthViewmodel auth, {
  VoidCallback? onTap,
  bool reduceMotion = false,
}) async {
  // Every real start goes through the splash, which finishes this before the
  // form is reachable; the overlay only plays for a sign-in after it.
  await auth.initialize();

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: auth,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: LoginTransitionOverlay(child: child!),
        ),
        home: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: onTap,
              child: const Text('underneath'),
            ),
          ),
        ),
      ),
    ),
  );
}

class _FakeRepository extends AuthRepository {
  _FakeRepository({this.loginError}) : super(_FakeAuthService());

  final String? loginError;

  @override
  Future<User> login(String identifier, String password) async {
    if (loginError case final message?) throw AuthException(message);
    return const User(
      id: 4,
      username: 'cashier',
      email: 'cashier@queenbuilders.local',
      fullName: 'Maria Santos',
      role: null,
    );
  }

  @override
  Future<User?> restoreSession() async => null;
}

class _FakeAuthService extends AuthService {
  @override
  Future<AuthSession> login(String identifier, String password) async {
    throw const AuthException('not used in these tests');
  }

  @override
  Future<void> logout() async {}
}
