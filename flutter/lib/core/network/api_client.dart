import 'package:client/core/config/api_config.dart';
import 'package:client/core/network/paged.dart';
import 'package:client/core/network/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

/// Shared Django API client with persistent JWT authentication.
class ApiClient {
  ApiClient._internal();

  static final ApiClient instance = ApiClient._internal();

  static const _accessTokenKey = 'auth_access_token';
  static const _refreshTokenKey = 'auth_refresh_token';

  // Linux (non-web) uses shared_preferences to avoid the gnome-keyring prompt;
  // every other platform keeps the OS secret store. Injectable for tests.
  // See planning/cashier-workflow/decisions/01-linux-token-storage.md.
  TokenStore _store = tokenStoreForPlatform();

  @visibleForTesting
  set tokenStore(TokenStore store) => _store = store;
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

  /// The refresh token held RIGHT NOW, or null when signed out.
  ///
  /// Exposed because the token rotates: after every refresh the live credential
  /// is a different string from the one login returned, and only this client
  /// knows which of the chain is current. `AuthService.logout` hands this one to
  /// the server so it can be blacklisted (ENDPOINTS.md §auth — a garbage or
  /// already-rotated token is ignored; the current one is revoked).
  String? get refreshToken => _refreshToken;

  Future<void> restoreTokens() async {
    try {
      _accessToken = await _store.read(_accessTokenKey);
      _refreshToken = await _store.read(_refreshTokenKey);
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
    await _persistTokens();
  }

  /// Writes both held tokens to the store, never throwing.
  ///
  /// One writer for every path that changes the pair (login, refresh) so a
  /// rotated token cannot be kept in memory only and lost on the next launch.
  /// A store failure keeps the tokens in memory rather than failing the request.
  Future<void> _persistTokens() async {
    final accessToken = _accessToken;
    final refreshToken = _refreshToken;
    if (accessToken == null || refreshToken == null) return;
    try {
      await Future.wait([
        _store.write(_accessTokenKey, accessToken),
        _store.write(_refreshTokenKey, refreshToken),
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
        _store.delete(_accessTokenKey),
        _store.delete(_refreshTokenKey),
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
      // Same `dio` as every other call: the interceptor skips the refresh path
      // above, so there is no loop, and one client means one place to inspect
      // the traffic. (A second Dio here also hid the refresh from every test.)
      final response = await dio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh/',
        data: {'refresh': refreshToken},
      );
      final accessToken = response.data?['access'] as String?;
      if (accessToken == null) return false;

      // Rotation is ON server-side (`ROTATE_REFRESH_TOKENS` +
      // `BLACKLIST_AFTER_ROTATION`, Phase 2 Task 6): the token just spent is
      // blacklisted, so this NEW refresh is the only one that still works.
      // Dropping it 401s the NEXT refresh and signs the user out mid-shift.
      // Absent key = rotation off, so the current token stays valid.
      final rotated = response.data?['refresh'] as String?;
      _accessToken = accessToken;
      if (rotated != null && rotated.isNotEmpty) _refreshToken = rotated;
      await _persistTokens();
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

  /// POSTs [data], optionally with per-request [headers].
  ///
  /// [headers] exists for the `Idempotency-Key` the checkout contract requires
  /// (ENDPOINTS.md, *Idempotency*): it is per REQUEST, not per client, because a
  /// new sale must carry a new key while a retry of the same sale reuses one.
  Future<Response<T>> post<T>(
    String path, {
    Object? data,
    Map<String, String>? headers,
  }) {
    return dio.post<T>(
      path,
      data: data,
      options: headers == null ? null : Options(headers: headers),
    );
  }
}
