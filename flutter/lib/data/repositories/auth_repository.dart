import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/services/auth_service.dart';

class AuthRepository {
  AuthRepository(this.authService, {ApiClient? client})
    : _client = client ?? ApiClient.instance;

  final AuthService authService;
  final ApiClient _client;

  Future<User> login(String identifier, String password) async {
    final session = await authService.login(identifier, password);
    await _client.saveTokens(
      accessToken: session.accessToken,
      refreshToken: session.refreshToken,
    );
    return session.user;
  }

  Future<User?> restoreSession() async {
    await _client.restoreTokens();
    if (!_client.hasTokens) return null;

    try {
      return await authService.currentUser();
    } on AuthException {
      await _client.clearTokens();
      return null;
    }
  }

  Future<void> logout() async {
    await authService.logout();
    await _client.clearTokens();
  }
}
