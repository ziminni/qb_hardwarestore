// Phase 2 Task 7 (audit remediation) — the refresh rotation contract.
//
// The backend runs simplejwt with `ROTATE_REFRESH_TOKENS` **and**
// `BLACKLIST_AFTER_ROTATION` (P2 Task 6): `POST /auth/refresh/` answers with
// `{'access': ..., 'refresh': <NEW>}` and immediately blacklists the refresh
// token that was spent. A client that keeps the OLD refresh token therefore
// 401s on the NEXT refresh and signs the user out mid-shift.
//
// These tests drive the real interceptor (401 → refresh → retry) through a fake
// adapter, so they prove the wiring rather than a helper called directly.

import 'dart:convert';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/token_store.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Answers by path and records every request it saw, so a test can assert what
/// went over the wire — including the body of each refresh call.
class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options, int attempt) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options, requests.length);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

bool _isRefresh(RequestOptions options) =>
    options.path.contains('/api/v1/auth/refresh/');

List<Object?> _refreshBodies(_FakeAdapter adapter) => adapter.requests
    .where(_isRefresh)
    .map((request) => (request.data as Map<String, dynamic>)['refresh'])
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient client;
  _FakeAdapter? adapter;

  setUpAll(() {
    // init() is NOT idempotent (`dio` is `late final`), so it happens once and
    // only the adapter and the token store are swapped per test.
    client = ApiClient.instance..init();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    client.tokenStore = const PrefsTokenStore();
  });

  tearDown(() async {
    if (adapter != null) client.dio.httpClientAdapter = adapter!;
    adapter = null;
    client.tokenStore = tokenStoreForPlatform();
    await client.clearTokens();
  });

  void serve(
    ResponseBody Function(RequestOptions options, int attempt) respond,
  ) {
    adapter = _FakeAdapter(respond);
    client.dio.httpClientAdapter = adapter!;
  }

  /// What actually reached the token store — the memory field alone would let a
  /// "kept it in RAM only" bug pass, and the app restores from the store on
  /// launch.
  Future<String?> storedRefresh() =>
      const PrefsTokenStore().read('auth_refresh_token');

  test(
    'refresh persists the NEW refresh token the server rotated in',
    () async {
      await client.saveTokens(
        accessToken: 'access-0',
        refreshToken: 'refresh-0',
      );

      serve((options, _) {
        if (_isRefresh(options)) {
          return _json({'access': 'access-1', 'refresh': 'refresh-1'});
        }
        return _json({'detail': 'expired'}, status: 401);
      });

      // The protected call still fails after the retry (the fake refuses every
      // non-refresh path); what matters is that the refresh ran.
      await expectLater(
        client.get<dynamic>('/api/v1/customers/'),
        throwsA(isA<DioException>()),
      );

      expect(_refreshBodies(adapter!), ['refresh-0']);
      expect(
        client.refreshToken,
        'refresh-1',
        reason: 'the token just spent is blacklisted server-side',
      );
      expect(
        await storedRefresh(),
        'refresh-1',
        reason: 'a restart restores from the store, not from memory',
      );
    },
  );

  /// A path that answers 401 the first time and 200 on the retry, which is the
  /// only way the interceptor's refresh-and-retry actually runs.
  ResponseBody expireOnce(Map<String, int> hits, RequestOptions options) {
    final seen = (hits[options.path] ?? 0) + 1;
    hits[options.path] = seen;
    return seen == 1
        ? _json({'detail': 'expired'}, status: 401)
        : _json({'ok': true});
  }

  test(
    'the second refresh sends the rotated token, not the blacklisted one',
    () async {
      await client.saveTokens(
        accessToken: 'access-0',
        refreshToken: 'refresh-0',
      );

      final hits = <String, int>{};
      var refreshed = 0;
      serve((options, _) {
        if (_isRefresh(options)) {
          refreshed++;
          return refreshed == 1
              ? _json({'access': 'access-1', 'refresh': 'refresh-1'})
              : _json({'access': 'access-2', 'refresh': 'refresh-2'});
        }
        return expireOnce(hits, options);
      });

      // Two separate 401s, so two refreshes. After the first rotation the second
      // refresh must present `refresh-1`; sending `refresh-0` again is exactly the
      // 401 that would log the cashier out.
      await client.get<dynamic>('/api/v1/customers/');
      await client.get<dynamic>('/api/v1/products/');

      expect(_refreshBodies(adapter!), ['refresh-0', 'refresh-1']);
      expect(client.refreshToken, 'refresh-2');
      expect(await storedRefresh(), 'refresh-2');
    },
  );

  test(
    'a refresh body without a rotated token keeps the one already held',
    () async {
      // Rotation could be switched off server-side; the client must not blank its
      // only remaining credential because the key was absent.
      await client.saveTokens(
        accessToken: 'access-0',
        refreshToken: 'refresh-0',
      );

      final hits = <String, int>{};
      serve((options, _) {
        if (_isRefresh(options)) return _json({'access': 'access-1'});
        return expireOnce(hits, options);
      });

      await client.get<dynamic>('/api/v1/customers/');

      expect(_refreshBodies(adapter!), ['refresh-0']);
      expect(client.refreshToken, 'refresh-0');
      expect(await storedRefresh(), 'refresh-0');
      expect(client.hasTokens, isTrue);
    },
  );

  test(
    'a refused refresh clears both tokens, so the user is sent to sign-in',
    () async {
      await client.saveTokens(
        accessToken: 'access-0',
        refreshToken: 'refresh-0',
      );

      serve((options, _) {
        if (_isRefresh(options)) {
          return _json({'detail': 'Token is blacklisted'}, status: 401);
        }
        return _json({'detail': 'expired'}, status: 401);
      });

      await expectLater(
        client.get<dynamic>('/api/v1/customers/'),
        throwsA(isA<DioException>()),
      );

      expect(client.refreshToken, isNull);
      expect(client.hasTokens, isFalse);
      expect(await storedRefresh(), isNull);
    },
  );
}
