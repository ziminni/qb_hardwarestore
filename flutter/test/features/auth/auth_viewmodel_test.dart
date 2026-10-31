// Card SYNC (P1): startup must survive a failing session restore.
//
// `initialize` used to await `repository.restoreSession()` unguarded, so a
// throwing secure-storage read (a missing keychain entitlement on a fresh
// desktop install, say) left `isInitializing` true forever and the app on a
// blank window. It also restored twice when two callers asked (the router and
// the splash both do), which means two token reads and two `/auth/me/` calls.

// FX1: a restore that never answers must not keep the app on the splash, and
// its late answer must not sign anybody in behind the login form
// (`AuthViewmodel.abandonRestore`).

import 'dart:async';

import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a throwing session restore falls back to the login screen', () async {
    final auth = AuthViewmodel(_FakeRepository(throwsOnRestore: true));
    var notifications = 0;
    auth.addListener(() => notifications++);

    await auth.initialize();

    expect(auth.user, isNull, reason: 'no session was restored');
    expect(
      auth.isInitializing,
      isFalse,
      reason: 'a listener waiting on this flag would hang on a blank window',
    );
    expect(
      notifications,
      greaterThan(0),
      reason: 'the router rebuilds on this notification, not on the flag alone',
    );
  });

  test(
    'initialize restores the session once however often it is called',
    () async {
      final repository = _FakeRepository();
      final auth = AuthViewmodel(repository);

      await Future.wait([auth.initialize(), auth.initialize()]);
      await auth.initialize();

      expect(repository.restoreCalls, 1);
      expect(auth.user?.username, 'stockmanager');
      expect(auth.isInitializing, isFalse);
    },
  );

  test('abandoning a hung restore resolves startup as signed out', () async {
    final gate = Completer<User?>();
    final repository = _FakeRepository(restoreGate: gate);
    final auth = AuthViewmodel(repository);
    var notifications = 0;
    auth.addListener(() => notifications++);

    final pending = auth.initialize();
    auth.abandonRestore();

    expect(auth.user, isNull, reason: 'no session was ever restored');
    expect(
      auth.isInitializing,
      isFalse,
      reason:
          'the router reads this flag; left true it parks every location on '
          'the splash, so the timeout never reaches the login form',
    );
    expect(notifications, greaterThan(0));

    // The restore answers much later: it must land nowhere.
    gate.complete(const User(
      id: 9,
      username: 'latecomer',
      email: 'late@queenbuilders.local',
      fullName: 'Late Comer',
      role: null,
    ));
    await pending;
    await Future<void>.delayed(Duration.zero);

    expect(
      auth.user,
      isNull,
      reason: 'an abandoned restore must not publish its late answer',
    );
  });

  test('signing in after an abandoned restore signs that account in', () async {
    final gate = Completer<User?>();
    final repository = _FakeRepository(restoreGate: gate);
    final auth = AuthViewmodel(repository);

    final pending = auth.initialize();
    auth.abandonRestore();

    final signedIn = await auth.login('cashier', 'demo1234');

    expect(signedIn, isTrue);
    expect(auth.user?.username, 'cashier');

    // The abandoned restore landing afterwards must not replace the account
    // the user just signed in as.
    gate.complete(const User(
      id: 9,
      username: 'latecomer',
      email: 'late@queenbuilders.local',
      fullName: 'Late Comer',
      role: null,
    ));
    await pending;
    await Future<void>.delayed(Duration.zero);

    expect(auth.user?.username, 'cashier');
  });
}

/// Counts restores and can fail or hang like a slow session lookup does.
class _FakeRepository extends AuthRepository {
  _FakeRepository({this.throwsOnRestore, this.restoreGate})
    : super(_FakeAuthService());

  final bool? throwsOnRestore;

  /// A restore that only answers when the test completes it.
  final Completer<User?>? restoreGate;
  int restoreCalls = 0;

  @override
  Future<User?> restoreSession() async {
    restoreCalls++;
    if (restoreGate != null) return restoreGate!.future;
    if (throwsOnRestore ?? false) {
      throw StateError('secure storage unavailable');
    }
    return const User(
      id: 7,
      username: 'stockmanager',
      email: 'stock@queenbuilders.local',
      fullName: 'Ana Reyes',
      role: null,
    );
  }

  @override
  Future<User> login(String identifier, String password) async {
    return User(
      id: 4,
      username: identifier,
      email: '$identifier@queenbuilders.local',
      fullName: 'Signed In',
      role: null,
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
