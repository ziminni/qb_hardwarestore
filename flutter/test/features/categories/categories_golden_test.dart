@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/categories/views/categories_page.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

/// The fallback visual check for K3 (00-shared/VERIFY.md, fallback 3): the real
/// Categories page, inside its real Stock Manager shell, painted with the real
/// fonts and written as PNGs into the SDD folder so the layout can be looked at
/// without a browser.
///
/// Opt in, so a font or platform difference never fails the normal suite:
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/categories/categories_golden_test.dart
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
    // The brand fonts stop at Latin, so anything the platform would fall back
    // for (a peso sign elsewhere in the shell) needs a system font here.
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
    testWidgets('categories grid at ${entry.$1} px', (tester) async {
      await _pumpCategories(tester, entry.$2, await _loadedStore());

      // The count is the card's new fact: one category holds four figures and a
      // grouped count, the long name has to survive two lines.
      expect(find.text('1,248 products'), findsOneWidget);
      expect(find.byType(ErrorBanner), findsNothing);

      await expectLater(
        find.byKey(pageKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/k3-list-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }

  testWidgets('categories empty at 760 px', (tester) async {
    await _pumpCategories(tester, const Size(760, 900), await _emptyStore());

    expect(find.text('No categories yet.'), findsOneWidget);
    // The filters are still offered, and the search field is not squeezed by
    // the New category button.
    expect(find.byType(FilterBar), findsOneWidget);
    expect(find.text('New category'), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/k3-empty-760.png')),
    );
  }, skip: !enabled);

  testWidgets('categories error at 760 px', (tester) async {
    await _pumpCategories(tester, const Size(760, 900), await _failedStore());

    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(find.text('Cannot connect to the BuildPro server.'), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/k3-error-760.png')),
    );
  }, skip: !enabled);
}

const pageKey = ValueKey('CategoriesPageGolden');

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

Future<void> _pumpCategories(
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
            textTheme: AppTheme.lightTheme.textTheme.apply(
              fontFamilyFallback: const [_pesoFallbackFamily],
            ),
          ),
          home: const CategoriesPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The Stock Manager the shell signs in as, so the sidebar shows the role the
/// screen belongs to.
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

/// Five categories: a big one whose count needs a thousands separator, one with
/// a name long enough to wrap, two ordinary ones and an archived one.
///
/// The products are generated rather than written out so the counts on screen are
/// counts of a real catalogue, not a number typed into the picture.
Future<InventoryViewmodel> _loadedStore() async {
  SharedPreferences.setMockInitialValues({});
  final categories = [
    category(id: 1, name: 'Cement and Aggregates'),
    category(id: 2, name: 'Deformed Steel Bars and Rebar Accessories'),
    category(id: 3, name: 'Plumbing'),
    category(id: 4, name: 'Electrical'),
    category(id: 5, name: 'Paint', isActive: false),
  ];
  final products = <Product>[
    for (var i = 0; i < 1248; i++)
      product(id: 1000 + i, name: 'Bulk item $i', categoryId: 1),
    for (var i = 0; i < 12; i++)
      product(id: 4000 + i, name: 'Steel bar $i', categoryId: 2),
    product(id: 5000, name: 'PVC Pipe 1/2 inch', categoryId: 3),
    product(id: 6000, name: 'Latex Paint White 4 L', categoryId: 5),
  ];
  final store = InventoryViewmodel(
    products: FakeProductsRepository(products: products),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(categories: categories),
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
    catalogue: FakeCatalogueRepository(categories: const []),
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
