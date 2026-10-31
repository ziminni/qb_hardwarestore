@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/user_service.dart';
import 'package:client/features/admin/viewmodels/admin_users_viewmodel.dart';
import 'package:client/features/admin/views/admin_user_management_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The fallback visual check (00-shared/VERIFY.md, fallback 3) for card A2: the
/// User Management list in BOTH shells, the empty and error states, and the
/// change-role dialog, rendered with the REAL fonts and theme into the SDD
/// folder.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/admin/a2_users_golden_test.dart
/// ```
void main() {
  const enabled = bool.fromEnvironment('RUN_GOLDENS');

  // Absolute on purpose: the PNGs belong to the SDD folder in the main
  // checkout, not next to this test inside the card's worktree.
  final goldenDir = Directory(
    '/home/yaji/projects/qb_ecosystem/qb_pos_inventory_system/'
    '.superpowers/sdd/ui-refresh/goldens',
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
    // Icons: the test harness does not load the Material icon font, so every
    // Icon would be a box in the PNG.
    final icons = _flutterSdkFile(
      'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons != null) await _loadFontFile('MaterialIcons', icons);
  });

  for (final entry in const [
    ('1440', Size(1440, 900)),
    ('1100', Size(1100, 900)),
    ('760', Size(760, 900)),
  ]) {
    testWidgets('user list in the admin shell at ${entry.$1} px', (
      tester,
    ) async {
      await _pump(tester, entry.$2, viewmodel: _viewmodel());
      await expectLater(
        find.byKey(_goldenKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/a2-list-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }

  testWidgets('the Store Manager shell at 1100 px', (tester) async {
    await _pump(
      tester,
      const Size(1100, 900),
      viewmodel: _viewmodel(),
      inSalesShell: true,
      roleCode: 'sales',
      roleLabel: 'Store Manager',
    );
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/a2-staff-1100.png')),
    );
  }, skip: !enabled);

  testWidgets('an empty list at 760 px', (tester) async {
    await _pump(
      tester,
      const Size(760, 900),
      viewmodel: _viewmodel(empty: true),
    );
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/a2-empty-760.png')),
    );
  }, skip: !enabled);

  testWidgets('a failed first load at 760 px', (tester) async {
    await _pump(
      tester,
      const Size(760, 900),
      viewmodel: _viewmodel(failure: 'The staff list could not be loaded.'),
    );
    await expectLater(
      find.byKey(_goldenKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/a2-error-760.png')),
    );
  }, skip: !enabled);

  testWidgets('the change-role dialog at 760 px', (tester) async {
    await _pump(tester, const Size(760, 900), viewmodel: _viewmodel());
    await tester.tap(find.text('Change role').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Change role for'), findsOneWidget);
    // The dialog lives in the app's overlay, so the whole app is the capture.
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile(Uri.file('${goldenDir.path}/a2-change-role-760.png')),
    );
  }, skip: !enabled);
}

const _goldenKey = ValueKey('AdminUsersGolden');

/// The roles the demo store really has.
const _admin = Role(id: 1, name: 'admin', displayName: 'Admin');
const _storeManager = Role(id: 3, name: 'sales', displayName: 'Store Manager');
const _stockManager = Role(
  id: 2,
  name: 'inventory',
  displayName: 'Stock Manager',
);
const _cashier = Role(id: 4, name: 'pos', displayName: 'Cashier');

/// Twelve accounts, ten active, two deactivated: the summary line says so, and
/// one row carries a long name plus a long email so the columns prove they
/// shorten instead of pushing the actions off the row.
const List<User> _accounts = [
  User(
    id: 1,
    username: 'admin',
    email: 'admin@qb.local',
    fullName: 'Ana Lopez',
    role: _admin,
  ),
  User(
    id: 2,
    username: 'manager',
    email: 'manager@qb.local',
    fullName: 'Mana Ger',
    role: _storeManager,
  ),
  User(
    id: 3,
    username: 'stocker',
    email: 'stocker@qb.local',
    fullName: 'Ben Cruz',
    role: _stockManager,
  ),
  User(
    id: 4,
    username: 'cashier',
    email: 'cashier@qb.local',
    fullName: 'Maria Santos',
    role: _cashier,
  ),
  User(
    id: 5,
    username: 'rosario.delacruz.mendoza',
    email: 'rosario.delacruz.mendoza@quickserve-builders.ph',
    fullName: 'Rosario Dela Cruz Mendoza',
    role: _cashier,
  ),
  User(
    id: 6,
    username: 'j.pascual',
    email: 'j.pascual@qb.local',
    fullName: 'Jose Pascual',
    role: _cashier,
  ),
  User(
    id: 7,
    username: 'l.reyes',
    email: 'l.reyes@qb.local',
    fullName: 'Liza Reyes',
    role: _cashier,
    isActive: false,
  ),
  User(
    id: 8,
    username: 'r.operator',
    email: 'root@qb.local',
    fullName: 'Root Operator',
    role: null,
  ),
  User(
    id: 9,
    username: 't.garcia',
    email: 't.garcia@qb.local',
    fullName: 'Tomas Garcia',
    role: _cashier,
  ),
  User(
    id: 10,
    username: 'g.navarro',
    email: 'g.navarro@qb.local',
    fullName: 'Grace Navarro',
    role: _cashier,
    isActive: false,
  ),
  User(
    id: 11,
    username: 'p.lim',
    email: 'p.lim@qb.local',
    fullName: 'Paolo Lim',
    role: _cashier,
  ),
  User(
    id: 12,
    username: 's.uy',
    email: 's.uy@qb.local',
    fullName: 'Sofia Uy',
    role: _cashier,
  ),
];

const _stats = UserStats(total: 12, active: 10, inactive: 2, rolesAssigned: 4);

/// Answers from memory; no PNG depends on a server.
class _StubUsers extends UserService {
  _StubUsers({this.rows = _accounts, this.failure, this.stats = _stats})
    : super();

  final List<User> rows;
  final String? failure;
  final UserStats stats;

  @override
  Future<List<User>> fetchUsers({String? search}) async {
    final failure = this.failure;
    if (failure != null) throw UsersServiceException(failure);
    return rows;
  }

  @override
  Future<UserStats> fetchUserStats() async {
    final failure = this.failure;
    if (failure != null) throw UsersServiceException(failure);
    return stats;
  }
}

/// `empty: true` is a store with no accounts at all (zeroes in the summary);
/// `failure` is a read that did not answer.
AdminUsersViewmodel _viewmodel({bool empty = false, String? failure}) {
  return AdminUsersViewmodel(
    users: _StubUsers(
      rows: empty ? const [] : _accounts,
      failure: failure,
      stats: empty
          ? const UserStats(total: 0, active: 0, inactive: 0, rolesAssigned: 0)
          : _stats,
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Size size, {
  required AdminUsersViewmodel viewmodel,
  bool inSalesShell = false,
  String roleCode = 'admin',
  String roleLabel = 'Admin',
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final auth = AuthViewmodel(AuthRepository(AuthService()))
    ..user = User(
      id: 1,
      username: 'admin',
      email: 'admin@qb.local',
      fullName: 'Ana Lopez',
      role: Role(id: 1, name: roleCode, displayName: roleLabel),
    );
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: auth,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: RepaintBoundary(
          key: _goldenKey,
          child: ColoredBox(
            color: AppTheme.lightTheme.colorScheme.surface,
            child: AdminUserManagementPage(
              viewmodel: viewmodel,
              inSalesShell: inSalesShell,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The logo is an asset image and image decoding does not run inside the fake
  // async zone: without this the brand renders as empty space. 42 is the full
  // sidebar's size, 40 the rail's.
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(_goldenKey));
    for (final logoSize in const [40, 42]) {
      await precacheImage(
        ResizeImage.resizeIfNeeded(
          logoSize,
          logoSize,
          const AssetImage(AppAssets.logo),
        ),
        context,
      );
    }
  });
  await tester.pumpAndSettle();
  expect(
    tester.takeException(),
    isNull,
    reason: 'a layout overflow would paint the yellow stripes into the PNG',
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
