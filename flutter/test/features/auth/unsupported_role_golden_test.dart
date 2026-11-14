@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/auth/views/unsupported_role_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The fallback visual check for L2 (00-shared/VERIFY.md, fallback 3): the real
/// Unsupported role page with the real fonts, written as PNGs into the SDD
/// folder so the layout can be looked at without a browser.
///
/// The page is standalone (it has no role shell; the router shows it in place of
/// every dashboard), so it is pumped as the app's `home`, exactly as its own
/// widget tests do.
///
/// Opt in, so a font or platform difference never fails the normal suite:
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/auth/unsupported_role_golden_test.dart
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
    if (icons != null) {
      await _loadFontFile('MaterialIcons', icons);
    }
  });

  // A CPMS-side account (the Site Foreman group is gone since decision 01, but
  // an older payload can still carry it): it has no POS dashboard, so the POS
  // shows the generic explanation. The PNGs below still prove the page holds
  // together with a role that has no screen.
  const foreman = _Account(
    'foreman',
    'foreman@demo.ph',
    'Fore Man',
    roleName: 'site_foreman',
    roleLabel: 'Site Foreman',
  );

  // The same screen for an account whose group was removed (a real state: the
  // staff list broke on `role: null`). Nothing to name, so no role pill.
  const noRole = _Account('root', 'root@demo.ph', 'Root Operator');

  // A label longer than the pill reads comfortably on one line at 760 px, so
  // the shot proves it degrades instead of clipping.
  const longLabel = _Account(
    'supervisor1',
    'supervisor1@demo.ph',
    'Maria Clara Santos',
    roleName: 'regional_warehouse_supervisor',
    roleLabel: 'Regional Warehouse Supervisor',
  );

  for (final entry in const [
    ('foreman', foreman, '1440', Size(1440, 900)),
    ('foreman', foreman, '760', Size(760, 900)),
    ('no-role', noRole, '1440', Size(1440, 900)),
    ('no-role', noRole, '760', Size(760, 900)),
  ]) {
    testWidgets('${entry.$1} state at ${entry.$3} px', (tester) async {
      await _pump(tester, entry.$2, entry.$4);

      expect(find.text('Sign out'), findsOneWidget);

      await expectLater(
        find.byKey(pageKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/l2-${entry.$1}-${entry.$3}.png'),
        ),
      );
    }, skip: !enabled);
  }

  testWidgets('long role label at 760 px', (tester) async {
    await _pump(tester, longLabel, const Size(760, 900));

    expect(find.text('Regional Warehouse Supervisor'), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/l2-long-label-760.png')),
    );
  }, skip: !enabled);
}

const pageKey = ValueKey('UnsupportedRolePageGolden');

class _Account {
  const _Account(
    this.username,
    this.email,
    this.fullName, {
    this.roleName,
    this.roleLabel,
  });

  final String username;
  final String email;
  final String fullName;
  final String? roleName;
  final String? roleLabel;

  User get user => User(
    id: 1,
    username: username,
    email: email,
    fullName: fullName,
    role: roleName == null
        ? null
        : Role(id: 1, name: roleName!, displayName: roleLabel ?? roleName!),
  );
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

Future<void> _pump(WidgetTester tester, _Account account, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  // No network: the page reads the signed-in user the router has already
  // loaded, and nothing on it calls a service.
  final auth = AuthViewmodel(AuthRepository(AuthService()))
    ..user = account.user;

  await tester.pumpWidget(
    RepaintBoundary(
      key: pageKey,
      child: ChangeNotifierProvider<AuthViewmodel>.value(
        value: auth,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          home: const UnsupportedRolePage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
