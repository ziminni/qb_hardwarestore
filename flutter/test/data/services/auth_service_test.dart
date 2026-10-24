// Phase 2 Task 7 (audit remediation) — the auth contract the backend grew in P2 Task 6.
//
// Three facts from ENDPOINTS.md §auth drive these tests:
//
//   * `POST /auth/logout/` takes an optional `{'refresh': '<token>'}` and blacklists it.
//     Without the body the token survives until it expires, so a "logout" on a shared
//     till leaves a working credential behind. Local sign-out must still succeed.
//   * `POST /auth/login/` answers **429 LOGIN_LOCKED** after 5 failures, with a human
//     `detail` and a `retry_after` in seconds — the password is never checked.
//   * Rotation means the token the client holds is not the one it started with.

import 'dart:convert';
import 'dart:typed_data';

import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/token_store.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return respond(options);
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ApiClient client;
  _FakeAdapter? adapter;

  setUpAll(() {
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

  void serve(ResponseBody Function(RequestOptions options) respond) {
    adapter = _FakeAdapter(respond);
    client.dio.httpClientAdapter = adapter!;
  }

  AuthService service() => AuthService(client: client);

  group('logout', () {
    test(
      'sends the refresh token it holds, so the server can revoke it',
      () async {
        await client.saveTokens(
          accessToken: 'access-0',
          refreshToken: 'refresh-0',
        );
        serve((_) => ResponseBody.fromString('', 204));

        await service().logout();

        final logout = adapter!.requests.single;
        expect(logout.path, endsWith('/api/v1/auth/logout/'));
        expect(logout.data, {
          'refresh': 'refresh-0',
        }, reason: 'a logout without the body leaves a working token behind');
      },
    );

    test('sends no body when no refresh token is held', () async {
      serve((_) => ResponseBody.fromString('', 204));

      await service().logout();

      final logout = adapter!.requests.single;
      expect(logout.path, endsWith('/api/v1/auth/logout/'));
      expect(logout.data, isNull);
    });

    test('still signs out locally when the server refuses', () async {
      // A device that cannot reach the shop's server must still be signable-out;
      // otherwise the till is stuck on a session nobody can end.
      await client.saveTokens(
        accessToken: 'access-0',
        refreshToken: 'refresh-0',
      );
      serve((_) => _json({'detail': 'Server error'}, status: 500));

      await AuthRepository(service(), client: client).logout();

      expect(client.hasTokens, isFalse);
      expect(client.refreshToken, isNull);
      expect(await const PrefsTokenStore().read('auth_refresh_token'), isNull);
    });
  });

  group('login lockout', () {
    test(
      'a 429 LOGIN_LOCKED surfaces the server detail, which names the wait',
      () async {
        serve(
          (_) => _json({
            'code': 'LOGIN_LOCKED',
            'detail':
                'Too many failed sign-in attempts. Try again in 5 minutes.',
            'retry_after': 287,
          }, status: 429),
        );

        await expectLater(
          service().login('cashier1', 'wrong'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'message',
              'Too many failed sign-in attempts. Try again in 5 minutes.',
            ),
          ),
        );
      },
    );

    test(
      'a lockout with no detail still names the wait from retry_after',
      () async {
        // `retry_after` is the machine-readable half; a stripped detail must not
        // turn a lockout into "Authentication failed. Please try again." — advice
        // that is guaranteed to fail for the next four minutes.
        serve(
          (_) =>
              _json({'code': 'LOGIN_LOCKED', 'retry_after': 125}, status: 429),
        );

        await expectLater(
          service().login('cashier1', 'wrong'),
          throwsA(
            isA<AuthException>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('Too many failed sign-in attempts'),
                contains('3 minutes'),
              ),
            ),
          ),
        );
      },
    );

    test('a plain wrong password still shows the server reason', () async {
      serve(
        (_) => _json({
          'detail': 'No active account found with the given credentials',
        }, status: 401),
      );

      await expectLater(
        service().login('cashier1', 'wrong'),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            'No active account found with the given credentials',
          ),
        ),
      );
    });
  });
}
