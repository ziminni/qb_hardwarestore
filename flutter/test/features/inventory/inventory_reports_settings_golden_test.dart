@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_reports_page.dart';
import 'package:client/features/inventory/views/inventory_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

/// The fallback visual check for K10 (00-shared/VERIFY.md, fallback 3): the real
/// Reports and Settings pages, inside their real Stock Manager shell, painted
/// with the real fonts and written as PNGs into the SDD folder so the layout can
/// be looked at without a browser.
///
/// Opt in, so a font or platform difference never fails the normal suite:
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/inventory/inventory_reports_settings_golden_test.dart
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
    // The bundled brand fonts stop at Latin, so the peso sign on the value tile
    // needs a system font that carries it.
    for (final candidate in _pesoFontCandidates) {
      if (File(candidate).existsSync()) {
        await _loadFontFile(_pesoFallbackFamily, candidate);
        break;
      }
    }
  });

  for (final entry in const [
    ('1440', Size(1440, 900)),
    ('1100', Size(1100, 900)),
    ('760', Size(760, 900)),
  ]) {
    testWidgets('reports at ${entry.$1} px', (tester) async {
      await _pumpReports(tester, entry.$2, await _loadedStore());

      // A seven digit value and a long product name are in the picture, and the
      // manager footnote still says what this role cannot read.
      expect(find.text('₱3,690,360.00'), findsOneWidget);
      expect(
        find.textContaining('available to Store Managers and above'),
        findsOneWidget,
      );

      await expectLater(
        find.byKey(pageKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/k10-reports-loaded-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }

  testWidgets('reports empty at 760 px', (tester) async {
    await _pumpReports(tester, const Size(760, 900), await _emptyStore());

    expect(find.text('No stock records yet.'), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(
        Uri.file('${goldenDir.path}/k10-reports-empty-760.png'),
      ),
    );
  }, skip: !enabled);

  testWidgets('reports error at 760 px', (tester) async {
    await _pumpReports(tester, const Size(760, 900), await _failedStore());

    expect(find.text('Cannot connect to the BuildPro server.'), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(
        Uri.file('${goldenDir.path}/k10-reports-error-760.png'),
      ),
    );
  }, skip: !enabled);

  for (final entry in const [
    ('1100', Size(1100, 900)),
    ('760', Size(760, 900)),
  ]) {
    testWidgets('settings at ${entry.$1} px', (tester) async {
      await _pumpSettings(tester, entry.$2);

      expect(find.text('Store information'), findsOneWidget);
      expect(find.text('QB Hardware & Construction Supplies'), findsOneWidget);

      await expectLater(
        find.byKey(pageKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/k10-settings-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }
}

const pageKey = ValueKey('InventoryReportsSettingsGolden');

/// Stands in for the platform font the app itself falls back to for a glyph the
/// brand fonts do not have.
const String _pesoFallbackFamily = 'PesoFallback';

const List<String> _pesoFontCandidates = [
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  '/usr/share/fonts/TTF/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
  'C:/Windows/Fonts/arial.ttf',
];

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

Future<void> _pumpReports(
  WidgetTester tester,
  Size size,
  InventoryViewmodel store,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RepaintBoundary(
      key: pageKey,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>.value(
            value: _stockManagerAuth(),
          ),
          ChangeNotifierProvider<InventoryViewmodel>.value(value: store),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: const InventoryReportsPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpSettings(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    RepaintBoundary(
      key: pageKey,
      child: ChangeNotifierProvider<AuthViewmodel>.value(
        value: _stockManagerAuth(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme(),
          home: const InventorySettingsPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

ThemeData _theme() => AppTheme.lightTheme.copyWith(
  // Only the goldens: lets a peso sign fall back to the system font the app
  // itself uses, because the brand fonts stop at Latin.
  textTheme: AppTheme.lightTheme.textTheme.apply(
    fontFamilyFallback: const [_pesoFallbackFamily],
  ),
);

/// The Stock Manager the shell paints its sidebar for.
AuthViewmodel _stockManagerAuth() {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  auth.user = User(
    id: 4,
    username: 'stocker',
    email: 'stocker@qb.ph',
    fullName: 'Ana Lopez',
    role: const Role(id: 4, name: 'inventory', displayName: 'Stock Manager'),
  );
  return auth;
}

/// Four products: two below their reorder level, one out of stock, and a long
/// name that has to wrap. Value: 12000 x 245 + 60 x 12500 + 2 x 180 =
/// ₱3,690,360.00, seven digits, so the money tile has to group thousands.
Future<InventoryViewmodel> _loadedStore() async {
  SharedPreferences.setMockInitialValues({});
  final products = [
    product(
      id: 1,
      name: 'Portland Cement 40 kg',
      categoryName: 'Cement',
      variants: [variant(id: 1, productId: 1, name: '40 kg', threshold: 200)],
    ),
    product(
      id: 2,
      name: 'Deformed Steel Bar 10 mm x 6 m Grade 60',
      categoryName: 'Steel bars',
      variants: [
        variant(id: 2, productId: 2, name: '10 mm x 6 m', threshold: 80),
      ],
    ),
    product(
      id: 3,
      name: 'PVC Pipe',
      categoryName: 'Plumbing',
      variants: [variant(id: 3, productId: 3, name: '1/2 inch', threshold: 10)],
    ),
    product(
      id: 4,
      name: 'Latex Paint White 4 L',
      categoryName: 'Paint',
      variants: [variant(id: 4, productId: 4, name: 'Glossy', threshold: 10)],
    ),
  ];
  final store = InventoryViewmodel(
    products: FakeProductsRepository(
      products: products,
      batches: [
        batch(id: 1, variantId: 1, qty: 12000, cost: 245),
        batch(id: 2, variantId: 2, qty: 60, cost: 12500),
        batch(id: 3, variantId: 3, qty: 2, cost: 180),
        // Nothing left for the paint.
      ],
    ),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );
  await store.load();
  return store;
}

Future<InventoryViewmodel> _emptyStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = InventoryViewmodel(
    products: FakeProductsRepository(),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );
  await store.load();
  return store;
}

Future<InventoryViewmodel> _failedStore() async {
  SharedPreferences.setMockInitialValues({});
  final store = InventoryViewmodel(
    products: _FailingProductsRepository(),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );
  await store.load();
  return store;
}

/// Answers every catalogue read with the same transport failure the live app
/// shows when the BuildPro server is unreachable.
class _FailingProductsRepository extends ProductsRepository {
  _FailingProductsRepository() : super(ProductsService());

  @override
  Future<ProductsSnapshot> loadCatalogue() async =>
      throw const ProductsServiceException(
        'Cannot connect to the BuildPro server.',
      );
}
