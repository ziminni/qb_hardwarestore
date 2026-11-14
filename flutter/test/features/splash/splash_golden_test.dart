@Tags(['golden'])
library;

import 'dart:async';
import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/splash/views/splash_page.dart';
import 'package:client/routes/routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

/// The fallback visual check for the splash screen (00-shared/VERIFY.md,
/// fallback 3): the real page with the real fonts, written as PNGs into the SDD
/// folder so the frame can be looked at without a browser.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/splash/splash_golden_test.dart
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
    // The test harness does not load the Material icon font.
    final icons = _flutterSdkFile(
      'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons != null) await _loadFontFile('MaterialIcons', icons);
  });

  for (final entry in const [
    ('splash', '1440', Size(1440, 900)),
    ('splash', '760', Size(760, 900)),
  ]) {
    testWidgets('${entry.$1} at ${entry.$2} px', (tester) async {
      await _pump(tester, entry.$3);

      await expectLater(
        find.byKey(pageKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/${entry.$1}-${entry.$2}.png'),
        ),
      );
    }, skip: !enabled);
  }
}

const pageKey = ValueKey('SplashPageGolden');

Future<void> _pump(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  // A restore that never answers: the intro stays on screen instead of handing
  // over to the login screen mid-capture.
  final auth = AuthViewmodel(_PendingRestoreRepository());
  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashPage(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const Text('login')),
    ],
  );
  addTearDown(router.dispose);

  // Real async for the first frames: the logo is a JPEG decoded off the widget
  // tree, and a plain pump captures the frame before it lands.
  await tester.runAsync(() async {
    await tester.pumpWidget(
      RepaintBoundary(
        key: pageKey,
        child: ChangeNotifierProvider<AuthViewmodel>.value(
          value: auth,
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            routerConfig: router,
          ),
        ),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
  });
  // The intro starts after the first frame (so a restore that answers at once
  // cannot notify mid-build), then runs to a FIXED point, 1.0 s of 1.4 s:
  // logo, title, subtitle and ruler are in and the page has not handed over.
  // Deterministic, unlike pumpAndSettle, which would run past the hand-over.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1000));
}

class _PendingRestoreRepository extends AuthRepository {
  _PendingRestoreRepository() : super(_FakeAuthService());

  @override
  Future<User?> restoreSession() {
    return Completer<User?>().future;
  }
}

class _FakeAuthService extends AuthService {
  @override
  Future<AuthSession> login(String identifier, String password) async {
    throw const AuthException('not used in this golden');
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
