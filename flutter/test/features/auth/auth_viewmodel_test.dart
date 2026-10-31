// Card SYNC (P1): startup must survive a failing session restore.
//
// `initialize` used to await `repository.restoreSession()` unguarded, so a
// throwing secure-storage read (a missing keychain entitlement on a fresh
// desktop install, say) left `isInitializing` true forever and the app on a
// blank window. It also restored twice when two callers asked (the router and
// the splash both do), which means two token reads and two `/auth/me/` calls.

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
}

/// Counts restores and can fail like secure storage does.
class _FakeRepository extends AuthRepository {
  _FakeRepository({this.throwsOnRestore}) : super(_FakeAuthService());

  final bool? throwsOnRestore;
  int restoreCalls = 0;

  @override
  Future<User?> restoreSession() async {
    restoreCalls++;
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
}

class _FakeAuthService extends AuthService {
  @override
  Future<AuthSession> login(String identifier, String password) async {
    throw const AuthException('not used in these tests');
  }

  @override
  Future<void> logout() async {}
}
