import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:flutter/foundation.dart';

class AuthViewmodel extends ChangeNotifier {
  AuthViewmodel(this.repository);

  final AuthRepository repository;

  bool isInitializing = true;
  bool isLoading = false;
  User? user;
  String? error;

  bool get isAuthenticated => user != null;

  /// The server role name, or null for a role-less account.
  ///
  /// Nullable on purpose: `GET /auth/me/` really answers `role: null` for a
  /// groupless account, and [AppRoutes.redirectFor] turns that into the
  /// unsupported-role screen — never a dashboard and never a silent bounce to
  /// the login form (decision 04).
  String? get roleName => user?.role?.name;

  /// The first call's restore, shared by every later caller.
  Future<void>? _initialization;

  /// Which restore may still publish its result.
  ///
  /// Bumped when a restore is abandoned (the splash's timeout) or replaced by a
  /// sign-in: a restore started under an older generation answers into the
  /// void instead of signing someone in from behind the login form.
  int _restoreGeneration = 0;

  /// Restores the saved session once; further calls await the same future.
  ///
  /// Two callers ask at startup (the router's redirect and the splash), and
  /// a doubled restore means two token reads and two `/auth/me/` calls.
  Future<void> initialize() => _initialization ??= _restoreSession();

  /// Gives up on a restore that never answered (the splash's timeout).
  ///
  /// Startup counts as resolved with no session, so the router stops parking
  /// every location on the splash and the login form is reachable. The restore
  /// keeps running in the background; its late answer is dropped rather than
  /// published, because a user typing their password must not be moved to a
  /// dashboard by a lookup that started before the timeout.
  void abandonRestore() {
    if (!isInitializing) return;
    _restoreGeneration++;
    // A later `initialize()` would otherwise hand back this dead future.
    _initialization = null;
    isInitializing = false;
    notifyListeners();
  }

  Future<void> _restoreSession() async {
    final generation = _restoreGeneration;
    User? restored;
    try {
      // A session already in hand (a warm start) needs no restore.
      restored = user ?? await repository.restoreSession();
    } catch (_) {
      // Secure storage can fail (a missing keychain entitlement on a fresh
      // desktop install, say). Falling back to the login screen beats a blank
      // window: the splash would otherwise wait on `isInitializing` forever.
      restored = null;
    }
    // Abandoned or superseded while it was in flight: say nothing at all.
    if (generation != _restoreGeneration) return;
    user = restored;
    isInitializing = false;
    notifyListeners();
  }

  Future<bool> login(String identifier, String password) async {
    // A restore still in flight belongs to a previous session and must not
    // overwrite the account this sign-in is about to set.
    _restoreGeneration++;
    _initialization = null;

    isLoading = true;
    error = null;
    notifyListeners();

    try {
      user = await repository.login(identifier, password);
      return true;
    } on AuthException catch (exception) {
      user = null;
      error = exception.message;
      return false;
    } catch (_) {
      user = null;
      error = 'Something went wrong. Please try again.';
      return false;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    isLoading = true;
    notifyListeners();
    try {
      await repository.logout();
    } finally {
      user = null;
      error = null;
      isLoading = false;
      notifyListeners();
    }
  }
}
