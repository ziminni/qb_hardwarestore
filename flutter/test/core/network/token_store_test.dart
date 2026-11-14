import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/token_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrefsTokenStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('round-trips write, read and delete', () async {
      const store = PrefsTokenStore();
      expect(await store.read('auth_access_token'), isNull);
      await store.write('auth_access_token', 'abc');
      expect(await store.read('auth_access_token'), 'abc');
      await store.delete('auth_access_token');
      expect(await store.read('auth_access_token'), isNull);
    });
  });

  group('tokenStoreForPlatform', () {
    test('Linux non-web selects the prefs store (no keyring prompt)', () {
      expect(
        tokenStoreForPlatform(isWeb: false, platform: TargetPlatform.linux),
        isA<PrefsTokenStore>(),
      );
    });

    test('macOS selects the secure store', () {
      expect(
        tokenStoreForPlatform(isWeb: false, platform: TargetPlatform.macOS),
        isA<SecureTokenStore>(),
      );
    });

    test('Windows selects the secure store', () {
      expect(
        tokenStoreForPlatform(isWeb: false, platform: TargetPlatform.windows),
        isA<SecureTokenStore>(),
      );
    });

    test('web selects the secure store even when the platform is linux', () {
      expect(
        tokenStoreForPlatform(isWeb: true, platform: TargetPlatform.linux),
        isA<SecureTokenStore>(),
      );
    });
  });

  group('ApiClient with an injected prefs store', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));
    tearDown(() => ApiClient.instance.tokenStore = tokenStoreForPlatform());

    test('saveTokens then restoreTokens round-trips through the store', () async {
      ApiClient.instance.tokenStore = const PrefsTokenStore();
      await ApiClient.instance.saveTokens(accessToken: 'a', refreshToken: 'r');

      // Prove persistence, not just memory: a store that kept nothing would
      // leave hasTokens false after a fresh read from the store.
      await ApiClient.instance.restoreTokens();
      expect(ApiClient.instance.hasTokens, isTrue);

      await ApiClient.instance.clearTokens();
      await ApiClient.instance.restoreTokens();
      expect(ApiClient.instance.hasTokens, isFalse);
    });
  });
}
