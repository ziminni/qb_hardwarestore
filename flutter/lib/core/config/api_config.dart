import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Resolves the backend base URL for the current platform.
///
/// Override at run time (e.g. for a physical device on Wi-Fi) with:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000
/// or, on a phone, in the app (the Bodega Checker's Profile, Settings): a
/// saved address beats both, and clearing it goes back to them.
class ApiConfig {
  ApiConfig._();

  static const String _fromEnvironment = String.fromEnvironment('API_BASE_URL');

  static const savedKey = 'api_base_url';
  static String? _saved;

  /// The address saved on this device, or null. Read once at start-up.
  static String? get savedBaseUrl => _saved;

  static Future<void> loadSaved() async {
    final value = (await SharedPreferences.getInstance()).getString(savedKey);
    _saved = (value == null || value.trim().isEmpty) ? null : value.trim();
  }

  /// Saves [url] for this device (null clears it); the caller re-points the
  /// API client. `http://` is assumed when no scheme is typed.
  static Future<String> save(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = normalise(url);
    if (cleaned == null) {
      _saved = null;
      await prefs.remove(savedKey);
    } else {
      _saved = cleaned;
      await prefs.setString(savedKey, cleaned);
    }
    return baseUrl;
  }

  /// `192.168.8.105:8000` becomes `http://192.168.8.105:8000`; a trailing
  /// slash and `/api/v1` are dropped (the host root is what the client wants).
  static String? normalise(String? url) {
    var text = (url ?? '').trim();
    if (text.isEmpty) return null;
    if (!text.contains('://')) text = 'http://$text';
    text = text.replaceFirst(RegExp(r'/+$'), '');
    text = text.replaceFirst(RegExp(r'/api/v1$'), '');
    return text;
  }

  static String get baseUrl {
    if (_saved case final saved?) return saved;
    if (_fromEnvironment.isNotEmpty) return _fromEnvironment;

    // Flutter Web / desktop / iOS simulator run on the host machine.
    if (kIsWeb) return 'http://127.0.0.1:8000';

    // Android emulator maps the host loopback to 10.0.2.2.
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8000';
    }

    return 'http://127.0.0.1:8000';
  }
}
