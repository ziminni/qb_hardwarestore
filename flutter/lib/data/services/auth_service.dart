import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/user.dart';
import 'package:dio/dio.dart';

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthService {
  AuthService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  final ApiClient _client;

  Future<AuthSession> login(String identifier, String password) async {
    try {
      final response = await _client.post<Map<String, dynamic>>(
        '/api/v1/auth/login/',
        data: {'identifier': identifier, 'password': password},
      );
      final data = response.data;
      if (data == null) {
        throw const AuthException('The server returned an empty response.');
      }
      return AuthSession.fromJson(data);
    } on DioException catch (error) {
      throw AuthException(_messageFrom(error));
    } on FormatException {
      throw const AuthException('The server returned an invalid response.');
    } on TypeError {
      throw const AuthException('The server returned an invalid response.');
    }
  }

  Future<User> currentUser() async {
    try {
      final response = await _client.get<Map<String, dynamic>>(
        '/api/v1/auth/me/',
      );
      final data = response.data;
      if (data == null) {
        throw const AuthException('The server returned an empty response.');
      }
      return User.fromJson(data);
    } on DioException catch (error) {
      throw AuthException(_messageFrom(error));
    }
  }

  /// Signs out, revoking the refresh token held right now.
  ///
  /// The body is what makes sign-out stick: `POST /auth/logout/` blacklists the
  /// refresh token it is given, and the token is rotated several times a day, so
  /// the live one is [ApiClient.refreshToken] — not the one login returned.
  /// Without it the credential outlives the sign-out on a shared till.
  ///
  /// A server failure is swallowed deliberately: local sign-out must always
  /// succeed, and `AuthRepository.logout` clears the tokens regardless.
  Future<void> logout() async {
    final refreshToken = _client.refreshToken;
    try {
      await _client.post<void>(
        '/api/v1/auth/logout/',
        data: refreshToken == null ? null : {'refresh': refreshToken},
      );
    } on DioException {
      // Local logout must still succeed if the backend is unavailable.
    }
  }

  String _messageFrom(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic> && data['detail'] is String) {
      // The server's prose wins, and for a lockout it already names the wait
      // ("Try again in 5 minutes.").
      return data['detail'] as String;
    }
    if (_serverCode(error) == _loginLockedCode) return _lockoutMessage(data);
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    return 'Authentication failed. Please try again.';
  }

  static const String _loginLockedCode = 'LOGIN_LOCKED';

  /// A lockout with no server prose still has to say how long.
  ///
  /// `429 LOGIN_LOCKED` (Phase 2 Task 6) means the password was never even
  /// checked, so `Authentication failed. Please try again.` sends the cashier into
  /// a retry that cannot work for minutes. `retry_after` is the machine-readable
  /// half; it rounds UP to whole minutes because "try again in 0 minutes" is not
  /// an instruction.
  String _lockoutMessage(Object? data) {
    final retryAfter = data is Map ? data['retry_after'] : null;
    const intro = 'Too many failed sign-in attempts.';
    if (retryAfter is num) {
      final minutes = (retryAfter / 60).ceil().clamp(1, 1 << 31);
      return '$intro Try again in $minutes minutes.';
    }
    return '$intro Wait a few minutes and try again.';
  }

  /// The stable machine-readable `code` a refusal carries, if any.
  String? _serverCode(DioException error) {
    final data = error.response?.data;
    if (data is! Map) return null;
    final code = data['code'];
    return code is String ? code : null;
  }
}
