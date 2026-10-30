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
  String? get roleName => user?.role.name;

  Future<void>? _initialization;

  // Safe to call more than once; the session is only restored the first time.
  Future<void> initialize() => _initialization ??= _restoreSession();

  Future<void> _restoreSession() async {
    try {
      user = await repository.restoreSession();
    } catch (_) {
      // Secure storage can fail (e.g. missing keychain entitlement); fall back
      // to the login screen instead of aborting startup.
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
