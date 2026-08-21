import 'package:dio/dio.dart';

import 'package:client/core/config/api_config.dart';

/// Central HTTP client (Dio singleton).
class ApiClient {
  ApiClient._internal();

  static final ApiClient instance = ApiClient._internal();

  late final Dio dio;

  /// Must be called once before any network request (in `main`).
  void init() {
    dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: {'Content-Type': 'application/json'},
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (error, handler) {
          if (error.response?.statusCode == 401) {
            // TODO: refresh token / trigger logout when auth is implemented.
          }
          return handler.next(error);
        },
      ),
    );
  }

  /// Reads the JWT access token.
  ///
  /// Replace with flutter_secure_storage (or similar) once authentication
  /// is implemented.
  String? _readToken() => null;

  Future<Response<dynamic>> get(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return dio.get(path, queryParameters: queryParameters);
  }
}