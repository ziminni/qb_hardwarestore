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

  /// Restores the saved session once; further calls await the same future.
  ///
  /// Two callers ask at startup (the router's redirect and the splash), and
  /// a doubled restore means two token reads and two `/auth/me/` calls.
  Future<void> initialize() => _initialization ??= _restoreSession();

  Future<void> _restoreSession() async {
    try {
      // A session already in hand (a warm start) needs no restore; startup is
      // resolved as soon as that is known, which is what the flag means.
      user ??= await repository.restoreSession();
    } catch (_) {
      // Secure storage can fail (a missing keychain entitlement on a fresh
      // desktop install, say). Falling back to the login screen beats a blank
      // window: the splash would otherwise wait on `isInitializing` forever.
      user = null;
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  Future<bool> login(String identifier, String password) async {
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
