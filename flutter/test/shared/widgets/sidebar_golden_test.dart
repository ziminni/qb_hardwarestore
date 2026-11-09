@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/layout/admin_skeleton_layout.dart';
import 'package:client/core/layout/inventory_skeleton_layout.dart';
import 'package:client/core/layout/sales_skeleton_layout.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/dashboard/widget/dashboard_shell.dart';
import 'package:client/features/pos/widgets/pos_navigation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// The fallback visual check (00-shared/VERIFY.md, fallback 3) for card F4:
/// every role's sidebar at 1440 (full), 1100 (rail) and 760 (drawer open),
/// rendered with the REAL fonts and written as PNGs into the SDD folder, so the
/// pattern can be looked at without a browser.
///
/// Same opt-in mechanism as F3's `components_golden_test.dart`: it only runs
/// when RUN_GOLDENS is passed, so the normal suite never fails on a font or
/// platform difference.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/shared/widgets/sidebar_golden_test.dart
/// ```
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
    // Icons: the test harness does not load the Material icon font, so every
    // Icon would be a box in the PNG.
    final icons = _flutterSdkFile(
      'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons != null) await _loadFontFile('MaterialIcons', icons);
  });

  for (final role in _roles) {
    for (final entry in const [
      ('1440', Size(1440, 1000), false),
      ('1100', Size(1100, 1000), false),
      ('760', Size(760, 1000), true),
    ]) {
      testWidgets('${role.name} sidebar at ${entry.$1} px', (tester) async {
        await _pumpShell(tester, role, entry.$2);
        if (entry.$3) {
          // The drawer only exists once opened: capture it open, not closed.
          await tester.tap(find.byTooltip('Open menu'));
          await tester.pumpAndSettle();
        }
        await expectLater(
          find.byKey(_galleryKey),
          matchesGoldenFile(
            Uri.file('${goldenDir.path}/f4-${role.name}-${entry.$1}.png'),
          ),
        );
      }, skip: !enabled);
    }
  }
}

const _galleryKey = ValueKey('SidebarGallery');

class _Role {
  const _Role(this.name, this.build);

  final String name;
  final Widget Function(Widget child) build;
}

/// One stub count per role that still HAS a marker, injected so no PNG depends
/// on a server. Each is keyed by the shell's OWN index constant: a hardcoded
/// number here once drew the stock manager's count on "Stock movements" while
/// production had been fixed to "Low stock".
///
/// The sales and admin shells now read the waiting-request count for their
/// "Requests from projects" entry (Phase 1b), and the count below is injected so
/// no PNG depends on a server.
const _roles = [
  _Role('cashier', _cashierShell),
  _Role('store-manager', _salesShell),
  _Role('stock-manager', _inventoryShell),
  _Role('admin', _adminShell),
];

Widget _cashierShell(Widget child) => DashboardShell(
  title: 'Point of Sale',
  subtitle: 'New transaction',
  selectedNavigationIndex: 1,
  navigationItems: posNavigationItems,
  onNavigationSelected: (_) {},
  loadMarkers: () async => const {DashboardShell.heldTransactionsIndex: 3},
  child: child,
);

Widget _salesShell(Widget child) => SalesSkeletonLayout(
  title: 'Store manager',
  subtitle: 'Transactions',
  selectedNavigationIndex: 1,
  onNavigationSelected: (_) {},
  child: child,
);

Widget _inventoryShell(Widget child) => InventorySkeletonLayout(
  title: 'Stock manager',
  subtitle: 'Products',
  selectedNavigationIndex: 0,
  onNavigationSelected: (_) {},
  loadMarkers: () async => const {InventorySkeletonLayout.lowStockIndex: 5},
  child: child,
);

Widget _adminShell(Widget child) => AdminSkeletonLayout(
  title: 'Admin',
  subtitle: 'Overview',
  // Index 4 is Reports now that Requisitions is gone, so the PNG still shows a
  // highlighted row that is not the first one.
  selectedNavigationIndex: 4,
  onNavigationSelected: (_) {},
  child: child,
);

Future<void> _pumpShell(WidgetTester tester, _Role role, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<AuthViewmodel>.value(
      value: AuthViewmodel(AuthRepository(AuthService())),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        // The real theme, with no per-gallery patches: the header title used to
        // fall back to Roboto here because AppTextTheme had no `titleLarge`.
        // That gap is fixed in the theme itself (see app_text_theme_test.dart),
        // so these PNGs show what the app actually renders.
        theme: AppTheme.lightTheme,
        home: RepaintBoundary(
          key: _galleryKey,
          child: ColoredBox(
            color: AppColors.background,
            child: role.build(const _SampleBody()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The logo is an asset image, and image decoding does not run inside the
  // fake async zone: without this the brand renders as empty space. Each size
  // the shell asks for is its own ResizeImage key (42 in the full sidebar, 40
  // in the rail), so both are warmed here.
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(_galleryKey));
    for (final size in const [40, 42]) {
      await precacheImage(
        ResizeImage.resizeIfNeeded(
          size,
          size,
          const AssetImage(AppAssets.logo),
        ),
        context,
      );
    }
  });
  await tester.pumpAndSettle();
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
