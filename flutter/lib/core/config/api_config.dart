import 'package:flutter/foundation.dart';

/// Resolves the backend base URL for the current platform.
///
/// Override at run time (e.g. for a physical device on Wi-Fi) with:
///   flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000
class ApiConfig {
  ApiConfig._();

  static const String _fromEnvironment = String.fromEnvironment('API_BASE_URL');

  static String get baseUrl {
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
