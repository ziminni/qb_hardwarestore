@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Phase 2 F2: the ONE sidebar a multi-area account gets, at 1440 (full), 1100
/// (icon rail) and 760 (drawer open), rendered with the REAL fonts and written
/// as PNGs beside the single-role gallery.
///
/// Three combinations only, and only their own new masters - the twelve
/// single-role captures in `sidebar_golden_test.dart` must stay byte-identical,
/// so this file never touches them:
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/shared/widgets/merged_sidebar_golden_test.dart
/// ```
///
/// Each combination is captured from a page of one of its OWN areas, so the
/// picture also shows which single merged row lights up.
void main() {
  const enabled = bool.fromEnvironment('RUN_GOLDENS');

  final goldenDir = Directory(
    '${Directory.current.path}/../.superpowers/sdd/ui-refresh/goldens',
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
    final icons = _flutterSdkFile(
      'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons != null) await _loadFontFile('MaterialIcons', icons);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final combo in _combos) {
    for (final entry in const [
      ('1440', Size(1440, 1000), false),
      ('1100', Size(1100, 1000), false),
      ('760', Size(760, 1000), true),
    ]) {
      testWidgets('${combo.name} merged sidebar at ${entry.$1} px', (
        tester,
      ) async {
        await _pumpShell(tester, combo, entry.$2);
        if (entry.$3) {
          // The drawer only exists once opened: capture it open, not closed.
          await tester.tap(find.byTooltip('Open menu'));
          await tester.pumpAndSettle();
        }
        await expectLater(
          find.byKey(_galleryKey),
          matchesGoldenFile(
            Uri.file('${goldenDir.path}/f2-${combo.name}-${entry.$1}.png'),
          ),
        );
      }, skip: !enabled);
    }
  }
}

const _galleryKey = ValueKey('MergedSidebarGallery');

class _Combo {
  const _Combo(this.name, this.roles, this.build);

  final String name;
  final List<Role> roles;
  final Widget Function(Widget child) build;
}

const _admin = Role(id: 1, name: 'admin', displayName: 'Admin');
const _sales = Role(id: 2, name: 'sales', displayName: 'Store Manager');
const _inventory = Role(id: 3, name: 'inventory', displayName: 'Stock Manager');
const _pos = Role(id: 4, name: 'pos', displayName: 'Cashier');

/// One stub count per picture. It is the page's OWN live count (the shell's
/// `markers`), which a merged sidebar draws by destination id: no PNG depends
/// on a server, and the count shows that the id - not a renumbered index - is
/// what carries it.
const _combos = [
  _Combo('cashier-store-manager', [_sales, _pos], _salesShell),
  _Combo('stock-manager-store-manager', [_inventory, _sales], _inventoryShell),
  _Combo('admin-cashier', [_admin, _pos], _adminShell),
];

Widget _salesShell(Widget child) => SalesSkeletonLayout(
  title: 'Store manager',
  subtitle: 'Payables',
  selectedNavigationIndex: 9,
  onNavigationSelected: (_) {},
  markers: const {SalesSkeletonLayout.projectRequestsIndex: 4},
  child: child,
);

Widget _inventoryShell(Widget child) => InventorySkeletonLayout(
  title: 'Stock manager',
  subtitle: 'Low stock',
  selectedNavigationIndex: InventorySkeletonLayout.lowStockIndex,
  onNavigationSelected: (_) {},
  markers: const {InventorySkeletonLayout.lowStockIndex: 3},
  child: child,
);

Widget _adminShell(Widget child) => AdminSkeletonLayout(
  title: 'Admin',
  subtitle: 'Project requests',
  selectedNavigationIndex: AdminSkeletonLayout.projectRequestsIndex,
  onNavigationSelected: (_) {},
  markers: const {AdminSkeletonLayout.projectRequestsIndex: 2},
  child: child,
);

Future<void> _pumpShell(WidgetTester tester, _Combo combo, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final auth = AuthViewmodel(_MergedAuthRepository(_account(combo.roles)));
  await auth.login('staff7', 'demo1234');

  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: auth,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: RepaintBoundary(
          key: _galleryKey,
          child: ColoredBox(
            color: AppColors.background,
            child: combo.build(const _SampleBody()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(_galleryKey));
    for (final image in tester.widgetList<Image>(find.byType(Image))) {
      await precacheImage(image.image, context);
    }
  });
  await tester.pumpAndSettle();
}

User _account(List<Role> roles) => User(
  id: 7,
  username: 'staff7',
  email: 'staff7@demo.ph',
  fullName: 'Staff Seven',
  role: roles.first,
  roles: roles,
);

class _MergedAuthRepository extends AuthRepository {
  _MergedAuthRepository(this.account) : super(_UnusedAuthService());

  final User account;

  @override
  Future<User?> restoreSession() async => account;

  @override
  Future<User> login(String identifier, String password) async => account;

  @override
  Future<void> logout() async {}
}

class _UnusedAuthService extends AuthService {
  @override
  Future<AuthSession> login(String identifier, String password) async {
    throw const AuthException('not used in this gallery');
  }

  @override
  Future<void> logout() async {}
}

/// Stands in for a page body: the sidebar is what this gallery is about.
class _SampleBody extends StatelessWidget {
  const _SampleBody();

  @override
  Widget build(BuildContext context) {
    return Text('Page content', style: Theme.of(context).textTheme.bodyMedium);
  }
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
