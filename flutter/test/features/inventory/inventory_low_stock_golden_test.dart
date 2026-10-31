@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_low_stock_page.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

/// The fallback visual check for K6 (00-shared/VERIFY.md, fallback 3): the real
/// Low stock page, inside its real Stock Manager shell, painted with the real
/// fonts and written as PNGs into the SDD folder so the layout can be looked at
/// without a browser.
///
/// Opt in, so a font or platform difference never fails the normal suite:
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/inventory/inventory_low_stock_golden_test.dart
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
    // The bundled brand fonts stop at Latin, so a peso sign needs a system font
    // that carries it (the purchase order dialog is not in these shots, but the
    // page shares the theme with the screens that print money).
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
    testWidgets('low stock list at ${entry.$1} px', (tester) async {
      await _pumpLowStock(tester, entry.$2, await _loadedStore());

      expect(find.byType(ErrorBanner), findsNothing);
      // Show the cleared alert too, so its muted style is in the picture.
      await tester.tap(find.text('Show resolved'));
      await tester.pumpAndSettle();
      if (entry.$2.width > 760) {
        // All five rows fit a table; the narrow window builds its cards lazily,
        // so the cleared one is below the fold in that shot.
        expect(find.text('Latex Paint White 4 L'), findsOneWidget);
      }

      await expectLater(
        find.byKey(pageKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/k6-low-stock-list-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }

  testWidgets('low stock empty at 760 px', (tester) async {
    await _pumpLowStock(tester, const Size(760, 900), await _emptyStore());

    expect(find.text('No low-stock alerts right now.'), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(
        Uri.file('${goldenDir.path}/k6-low-stock-empty-760.png'),
      ),
    );
  }, skip: !enabled);

  testWidgets('low stock error at 760 px', (tester) async {
    await _pumpLowStock(tester, const Size(760, 900), await _failedStore());

    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(find.text('Cannot connect to the BuildPro server.'), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(
        Uri.file('${goldenDir.path}/k6-low-stock-error-760.png'),
      ),
    );
  }, skip: !enabled);
}

const pageKey = ValueKey('InventoryLowStockPageGolden');

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

Future<void> _pumpLowStock(
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
          theme: AppTheme.lightTheme.copyWith(
            // Only the goldens: lets a peso sign fall back to the system font
            // the app itself uses, because the brand fonts stop at Latin.
            textTheme: AppTheme.lightTheme.textTheme.apply(
              fontFamilyFallback: const [_pesoFallbackFamily],
            ),
          ),
          home: const InventoryLowStockPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The Stock Manager the page reads its role CODE from (`inventory`), which is
/// what admits Resolve. The display label is what a person reads.
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

/// Five alerted variants: one out of stock, one with a long name and a seven
/// digit level, two plainly low, and one already cleared.
Future<InventoryViewmodel> _loadedStore() async {
  SharedPreferences.setMockInitialValues({});
  final products = [
    product(
      id: 1,
      name: 'Tiles 60x60',
      categoryName: 'Tiles',
      variants: [variant(id: 1, productId: 1, name: 'Glossy', threshold: 40)],
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
      name: 'Fill Sand',
      categoryName: 'Aggregates',
      variants: [
        variant(
          id: 4,
          productId: 4,
          name: 'Screened',
          threshold: 1200000,
          baseUomCode: 'CU.M',
        ),
      ],
    ),
    product(
      id: 5,
      name: 'Latex Paint White 4 L',
      categoryName: 'Paint',
      variants: [variant(id: 5, productId: 5, name: 'Glossy', threshold: 10)],
    ),
  ];
  final store = InventoryViewmodel(
    products: FakeProductsRepository(
      products: products,
      batches: [
        // Nothing left for the Tiles.
        batch(id: 2, variantId: 2, qty: 12),
        batch(id: 3, variantId: 3, qty: 2),
        // Seven digits, so the count column has to group thousands.
        batch(id: 4, variantId: 4, qty: 1199000),
        // Restocked after the alert was cleared.
        batch(id: 5, variantId: 5, qty: 26),
      ],
    ),
    inventory: FakeInventoryRepository(
      alerts: [
        alert(id: 1, variantId: 1, type: SystemAlertType.outOfStock),
        alert(id: 2, variantId: 2),
        alert(id: 3, variantId: 3),
        alert(id: 4, variantId: 4),
        alert(
          id: 5,
          variantId: 5,
          resolved: true,
          resolvedByName: 'Ana Lopez',
          resolvedAt: DateTime(2026, 10, 25, 14, 30),
        ),
      ],
    ),
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
