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
      final response = await _client.get<Map<String, dynamic>>('/api/v1/auth/me/');
      final data = response.data;
      if (data == null) {
        throw const AuthException('The server returned an empty response.');
      }
      return User.fromJson(data);
    } on DioException catch (error) {
      throw AuthException(_messageFrom(error));
    }
  }

  Future<void> logout() async {
    try {
      await _client.post<void>('/api/v1/auth/logout/');
    } on DioException {
      // Local logout must still succeed if the backend is unavailable.
    }
  }

  String _messageFrom(DioException error) {
    final data = error.response?.data;
    if (data is Map<String, dynamic> && data['detail'] is String) {
      return data['detail'] as String;
    }
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    return 'Authentication failed. Please try again.';
  }
}
