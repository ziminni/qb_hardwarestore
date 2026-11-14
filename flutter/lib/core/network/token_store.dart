import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A minimal key/value sink for the two JWT keys. One seam so the platform
/// choice is a single decision, and tests can inject a store instead of
/// depending on the host OS. See
/// `planning/cashier-workflow/decisions/01-linux-token-storage.md`.
abstract class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The OS secret store — macOS Keychain, Windows DPAPI, mobile keystore, web
/// browser storage. The macOS option is carried verbatim from the original
/// `ApiClient` so that platform is unchanged by this seam.
class SecureTokenStore implements TokenStore {
  const SecureTokenStore([
    this._storage = const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// Linux (non-web) store. `flutter_secure_storage` on Linux routes through
/// `libsecret` → gnome-keyring, which prompts to create/unlock a keyring on
/// every run in a headless/WSL session where nothing unlocks one at login.
/// Plain `shared_preferences` has no such prompt. The cost — a plaintext token
/// file — is accepted by decision 01 (production hardening is out of scope).
class PrefsTokenStore implements TokenStore {
  const PrefsTokenStore();

  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async =>
      (await SharedPreferences.getInstance()).setString(key, value);

  @override
  Future<void> delete(String key) async =>
      (await SharedPreferences.getInstance()).remove(key);
}

/// Picks the store for the running platform.
///
/// Uses `defaultTargetPlatform` rather than `dart:io`'s `Platform.isLinux`:
/// `dart:io` does not compile on web, and in `flutter test` this reports
/// `android` by default, so unit tests keep the secure path unless they pass
/// an explicit [platform]. The real Linux desktop reports
/// `TargetPlatform.linux` and gets the prompt-free prefs store.
TokenStore tokenStoreForPlatform({
  bool isWeb = kIsWeb,
  TargetPlatform? platform,
}) {
  final target = platform ?? defaultTargetPlatform;
  if (!isWeb && target == TargetPlatform.linux) {
    return const PrefsTokenStore();
  }
  return const SecureTokenStore();
}
