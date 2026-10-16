import 'package:client/core/config/api_config.dart';
import 'package:client/core/network/paged.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Shared Django API client with persistent JWT authentication.
class ApiClient {
  ApiClient._internal();

  static final ApiClient instance = ApiClient._internal();

  static const _accessTokenKey = 'auth_access_token';
  static const _refreshTokenKey = 'auth_refresh_token';

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );
  late final Dio dio;
  String? _accessToken;
  String? _refreshToken;
  Future<bool>? _refreshOperation;

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
          if (_accessToken case final token? when token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          final request = error.requestOptions;
          final isAuthenticationEndpoint =
              request.path.contains('/api/v1/auth/login/') ||
              request.path.contains('/api/v1/auth/refresh/');
          final alreadyRetried = request.extra['jwtRetried'] == true;

          if (error.response?.statusCode == 401 &&
              !isAuthenticationEndpoint &&
              !alreadyRetried &&
              _refreshToken != null) {
            final refreshed = await _refreshOnce();
            if (refreshed) {
              request.extra['jwtRetried'] = true;
              request.headers['Authorization'] = 'Bearer $_accessToken';
              try {
                handler.resolve(await dio.fetch<dynamic>(request));
                return;
              } on DioException catch (retryError) {
                handler.next(retryError);
                return;
              }
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  bool get hasTokens => _accessToken != null && _refreshToken != null;

  Future<void> restoreTokens() async {
    try {
      _accessToken = await _storage.read(key: _accessTokenKey);
      _refreshToken = await _storage.read(key: _refreshTokenKey);
    } catch (_) {
      _accessToken = null;
      _refreshToken = null;
    }
  }

  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    try {
      await Future.wait([
        _storage.write(key: _accessTokenKey, value: accessToken),
        _storage.write(key: _refreshTokenKey, value: refreshToken),
      ]);
    } catch (_) {
      // Keep tokens in memory even if secure storage fails
    }
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    try {
      await Future.wait([
        _storage.delete(key: _accessTokenKey),
        _storage.delete(key: _refreshTokenKey),
      ]);
    } catch (_) {
      // Ignored
    }
  }

  Future<bool> _refreshOnce() {
    return _refreshOperation ??= _refreshAccessToken().whenComplete(() {
      _refreshOperation = null;
    });
  }

  Future<bool> _refreshAccessToken() async {
    final refreshToken = _refreshToken;
    if (refreshToken == null) return false;

    try {
      final refreshClient = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));
      final response = await refreshClient.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh/',
        data: {'refresh': refreshToken},
      );
      final accessToken = response.data?['access'] as String?;
      if (accessToken == null) return false;
      _accessToken = accessToken;
      await _storage.write(key: _accessTokenKey, value: accessToken);
      return true;
    } on DioException {
      await clearTokens();
      return false;
    }
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
  }) {
    return dio.get<T>(path, queryParameters: queryParameters);
  }

  /// GETs a **list** endpoint and unwraps the pagination envelope.
  ///
  /// Every list route returns `{count, next, previous, results}`. That envelope
  /// is unwrapped in exactly one place — [parsePaged] — so no repository and no
  /// screen has to know its shape (decision 03).
  ///
  /// Prefer this over [get] for any list route: [get] hands back the envelope
  /// itself, which is almost never what a caller wants.
  ///
  /// The body is fetched as `dynamic` deliberately. Asking Dio for
  /// `Map<String, dynamic>` would throw a type error before [parsePaged] could
  /// report what actually arrived, and that report is the more useful failure.
  Future<Paged<T>> getList<T>(
    String path,
    T Function(Map<String, dynamic> json) fromJson, {
    Map<String, dynamic>? queryParameters,
  }) async {
    final response = await dio.get<dynamic>(
      path,
      queryParameters: queryParameters,
    );
    return parsePaged<T>(response.data, fromJson);
  }

  Future<Response<T>> post<T>(String path, {Object? data}) {
    return dio.post<T>(path, data: data);
  }
}
