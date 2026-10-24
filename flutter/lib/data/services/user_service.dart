import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/user.dart';
import 'package:dio/dio.dart';

class UsersServiceException implements Exception {
  const UsersServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reads and creates staff accounts over the admin users endpoints.
///
/// The list and the stats are both admin-only server-side
/// (`IsAdminUser`); a non-admin caller gets a 403, which surfaces as a
/// permission error rather than a load error. Creation posts the register
/// shape, which mandates a group. The LIST can still contain a role-less
/// account (`createsuperuser`, a group removed in the Django admin), so
/// `User.role` is nullable and such a row renders "No role" instead of
/// failing the whole list (Phase 3 Task 0).
class UserService {
  UserService({ApiClient? client}) : _client = client ?? ApiClient.instance;

  static const usersPath = '/api/v1/users/';
  static const statsPath = '/api/v1/users/stats/';
  static const registerPath = '/api/v1/auth/register/';

  final ApiClient _client;

  Future<List<User>> fetchUsers({String? search}) async {
    try {
      final query = <String, dynamic>{};
      if (search != null && search.isNotEmpty) query['search'] = search;
      final page = await _client.getList<User>(
        usersPath,
        User.fromJson,
        queryParameters: query.isEmpty ? null : query,
      );
      return page.items.toList();
    } on DioException catch (error) {
      throw UsersServiceException(
        _message(error, 'The staff list could not be loaded.'),
      );
    }
    // getList parses rows eagerly, so a malformed row throws HERE, not at
    // items.toList(). It must read as a load error with a retry — never a raw
    // crash that blanks the whole staff list with no message. A NULL role is
    // no longer malformed (see [User.role]); a non-object role still is.
    on FormatException catch (error) {
      throw UsersServiceException(
        'The staff list could not be read: ${error.message}',
      );
    }
  }

  Future<UserStats> fetchUserStats() async {
    try {
      final response = await _client.dio.get<Map<String, dynamic>>(statsPath);
      final data = response.data;
      if (data == null) throw const FormatException('Empty stats response');
      return UserStats.fromJson(data);
    } on DioException catch (error) {
      throw UsersServiceException(
        _message(error, 'The account summary could not be loaded.'),
      );
    } on FormatException catch (error) {
      throw UsersServiceException(error.message);
    }
  }

  Future<User> createUser({
    required String username,
    required String email,
    required String fullName,
    required String password,
    required String groupName,
  }) async {
    try {
      final response = await _client.dio.post<Map<String, dynamic>>(
        registerPath,
        data: {
          'username': username,
          'email': email,
          'full_name': fullName,
          'password': password,
          'group_name': groupName,
        },
      );
      final data = response.data;
      if (data == null) throw const FormatException('Empty create response');
      return User.fromJson(data);
    } on DioException catch (error) {
      throw UsersServiceException(
        _message(error, 'The account could not be created.'),
      );
    } on FormatException catch (error) {
      throw UsersServiceException(error.message);
    }
  }

  String _message(DioException error, String fallback) {
    if (error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout) {
      return 'Cannot connect to the BuildPro server.';
    }
    if (error.response?.statusCode == 401) {
      return 'Your session has expired. Sign in again.';
    }
    if (error.response?.statusCode == 403) {
      return 'You do not have permission to manage accounts.';
    }
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final detail = data['detail'];
      if (detail is String) return detail;
      for (final entry in data.values) {
        if (entry is List && entry.isNotEmpty && entry.first is String) {
          return entry.first as String;
        }
      }
    }
    return fallback;
  }
}
