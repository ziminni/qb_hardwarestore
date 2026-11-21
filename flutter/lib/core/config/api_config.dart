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
  static const String _gatewayKeyFromEnvironment = String.fromEnvironment(
    'API_GATEWAY_KEY',
  );
  static const String _storeSmsFromEnvironment = String.fromEnvironment(
    'STORE_SMS_NUMBER',
  );

  static const savedKey = 'api_base_url';
  static const savedGatewayKeyPref = 'api_gateway_key';
  static const savedStoreSmsPref = 'store_sms_number';
  static String? _saved;
  static String? _savedGatewayKey;
  static String? _savedStoreSms;

  /// The address saved on this device, or null. Read once at start-up.
  static String? get savedBaseUrl => _saved;

  /// The optional tunnel gateway key (`X-QB-Gateway-Key`) saved on this device.
  static String? get savedGatewayKey => _savedGatewayKey;

  /// The optional store GSM modem phone number for offline Bodega SMS replies.
  static String? get savedStoreSmsNumber => _savedStoreSms;

  /// Active gateway key to send on requests (saved value overrides compile-time).
  static String get gatewayKey =>
      _savedGatewayKey ?? _gatewayKeyFromEnvironment;

  /// Active store SMS modem phone number (saved value overrides compile-time).
  static String get storeSmsNumber =>
      _savedStoreSms ?? _storeSmsFromEnvironment;

  static Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(savedKey);
    _saved = (value == null || value.trim().isEmpty) ? null : value.trim();
    final gw = prefs.getString(savedGatewayKeyPref);
    _savedGatewayKey = (gw == null || gw.trim().isEmpty) ? null : gw.trim();
    final sms = prefs.getString(savedStoreSmsPref);
    _savedStoreSms = (sms == null || sms.trim().isEmpty) ? null : sms.trim();
  }

  /// Saves [number] for offline SMS fallback (null/empty clears it).
  static Future<void> saveStoreSmsNumber(String? number) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = (number ?? '').trim();
    if (cleaned.isEmpty) {
      _savedStoreSms = null;
      await prefs.remove(savedStoreSmsPref);
    } else {
      _savedStoreSms = cleaned;
      await prefs.setString(savedStoreSmsPref, cleaned);
    }
  }

  /// Saves [key] for this device (null/empty clears it).
  static Future<void> saveGatewayKey(String? key) async {
    final prefs = await SharedPreferences.getInstance();
    final cleaned = (key ?? '').trim();
    if (cleaned.isEmpty) {
      _savedGatewayKey = null;
      await prefs.remove(savedGatewayKeyPref);
    } else {
      _savedGatewayKey = cleaned;
      await prefs.setString(savedGatewayKeyPref, cleaned);
    }
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
