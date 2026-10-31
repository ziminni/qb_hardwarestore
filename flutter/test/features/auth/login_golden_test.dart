@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/network/api_client.dart';
import 'package:client/core/network/token_store.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/remembered_login_store.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/views/login_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The fallback visual check for L1 (00-shared/VERIFY.md, fallback 3): the real
/// login page with the real fonts, written as PNGs into the SDD folder so the
/// layout can be looked at without a browser.
///
/// The page is standalone (the router shows it as the app's `home`), so it is
/// pumped the same way its widget tests pump it: a fake auth service, tokens in
/// memory, preferences seeded with the remembered username.
///
/// Opt in, so a font or platform difference never fails the normal suite:
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/auth/login_golden_test.dart
/// ```
void main() {
  const enabled = bool.fromEnvironment('RUN_GOLDENS');

  // Absolute: the PNGs belong to the MAIN checkout's SDD folder, not to this
  // card's worktree.
  final goldenDir = Directory(
    '/home/yaji/projects/qb_ecosystem/qb_pos_inventory_system'
    '/.superpowers/sdd/ui-refresh/goldens',
  );

  setUpAll(() async {
    goldenDir.createSync(recursive: true);
    await _loadFont('Cinzel', const [
      'Cinzel-Regular.ttf',
      'Cinzel-Medium.ttf',
      'Cinzel-Bold.ttf',
    ]);
    await _loadFont('OpenSans', const [
      'OpenSans-Regular.ttf',
      'OpenSans-Medium.ttf',
      'OpenSans-Bold.ttf',
    ]);
    // The test harness does not load the Material icon font, so every Icon
    // would be a box in the PNG.
    final icons = _flutterSdkFile(
      'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons != null) await _loadFontFile('MaterialIcons', icons);
  });

  for (final entry in const [
    ('default', '1440', Size(1440, 900)),
    ('default', '1100', Size(1100, 900)),
    ('default', '760', Size(760, 900)),
    ('error', '760', Size(760, 900)),
  ]) {
    testWidgets('${entry.$1} state at ${entry.$2} px', (tester) async {
      await _pump(tester, entry.$3, failSignIn: entry.$1 == 'error');

      await expectLater(
        find.byKey(pageKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/l1-${entry.$1}-${entry.$2}.png'),
        ),
      );
    }, skip: !enabled);
  }
}

const pageKey = ValueKey('LoginPageGolden');

/// What a wrong password reaches the user as: the login endpoint answers with a
/// serializer error and no `detail`, which `AuthService` maps to this sentence.
const _wrongPassword = 'Authentication failed. Please try again.';

/// A real demo identifier, long enough to prove the field holds an email.
const _rememberedUsername = 'maria.santos@queenbuilders.local';

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  required bool failSignIn,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{
    RememberedLoginStore.usernameKey: _rememberedUsername,
  });
  // The real token store is a platform plugin that never answers under
  // `flutter test`; the keys are irrelevant to the picture.
  ApiClient.instance.tokenStore = _MemoryTokenStore();

  final auth = AuthViewmodel(
    AuthRepository(
      _FakeAuthService(loginError: failSignIn ? _wrongPassword : null),
    ),
  );

  // Real async for the first frames: the brand logo is a JPEG decoded off the
  // widget tree, and a plain pump captures the frame before it lands.
  await tester.runAsync(() async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: pageKey,
        child: ChangeNotifierProvider<AuthViewmodel>.value(
          value: auth,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            home: const LoginPage(),
          ),
        ),
      ),
    );
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  await tester.pumpAndSettle();

  if (!failSignIn) return;

  await tester.enterText(
    find.widgetWithText(TextFormField, 'Enter your password'),
    'wrong-password',
  );
  await tester.tap(find.text('Sign in'));
  await tester.pumpAndSettle();
}

class _MemoryTokenStore implements TokenStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// Signs the remembered account in, or refuses with [loginError].
class _FakeAuthService extends AuthService {
  _FakeAuthService({this.loginError});

  final String? loginError;

  @override
  Future<AuthSession> login(String identifier, String password) async {
    if (loginError case final message?) throw AuthException(message);
    return const AuthSession(
      accessToken: 'access',
      refreshToken: 'refresh',
      user: User(
        id: 4,
        username: 'cashier',
        email: _rememberedUsername,
        fullName: 'Maria Santos',
        role: null,
      ),
    );
  }

  @override
  Future<void> logout() async {}
}

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    final bytes = await File('assets/fonts/$file').readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

Future<void> _loadFontFile(String family, String path) async {
  final loader = FontLoader(family);
  final bytes = await File(path).readAsBytes();
  loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

/// The running Flutter SDK, found from the environment or from the dart binary
/// that is executing this test.
String? _flutterSdkFile(String relativePath) {
  final candidates = <String>[
    if (Platform.environment['FLUTTER_ROOT'] case final root?)
      '$root/$relativePath',
  ];
  var dir = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 6; depth++) {
    candidates.add('${dir.path}/$relativePath');
    dir = dir.parent;
  }
  for (final path in candidates) {
    if (File(path).existsSync()) return path;
  }
  return null;
}
