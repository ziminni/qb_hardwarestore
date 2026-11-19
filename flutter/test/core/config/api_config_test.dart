// A server address saved on the phone (owner 2026-11-18): it beats the build's
// default, and clearing it goes back to that default.

import 'package:client/core/config/api_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ApiConfig.save(null));

  test('a typed address becomes the host root the client wants', () {
    expect(
      ApiConfig.normalise('192.168.8.105:8000'),
      'http://192.168.8.105:8000',
    );
    expect(
      ApiConfig.normalise(' http://pos.local:8000/ '),
      'http://pos.local:8000',
    );
    expect(
      ApiConfig.normalise('http://pos.local:8000/api/v1'),
      'http://pos.local:8000',
    );
    expect(
      ApiConfig.normalise('https://x.trycloudflare.com'),
      'https://x.trycloudflare.com',
    );
    expect(ApiConfig.normalise('  '), isNull);
  });

  test(
    'a saved address wins, survives a restart, and clearing restores the default',
    () async {
      final before = ApiConfig.baseUrl;

      expect(
        await ApiConfig.save('192.168.8.105:8000'),
        'http://192.168.8.105:8000',
      );
      expect(ApiConfig.baseUrl, 'http://192.168.8.105:8000');

      await ApiConfig.loadSaved();
      expect(ApiConfig.savedBaseUrl, 'http://192.168.8.105:8000');

      expect(await ApiConfig.save(null), before);
      await ApiConfig.loadSaved();
      expect(ApiConfig.savedBaseUrl, isNull);
    },
  );
}
