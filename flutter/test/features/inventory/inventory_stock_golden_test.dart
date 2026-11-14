@Tags(['golden'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_stock_page.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

/// The fallback visual check for K4 (00-shared/VERIFY.md, fallback 3): the real
/// Stock page, inside its real Stock Manager shell, painted with the real fonts
/// and written as PNGs into the SDD folder so the layout can be looked at without
/// a browser.
///
/// Opt in, so a font or platform difference never fails the normal suite:
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/inventory/inventory_stock_golden_test.dart
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
    // The bundled brand fonts stop at Latin, so a peso sign (and the tabular
    // digits' fallback) needs a system font that carries it.
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
    testWidgets('stock list at ${entry.$1} px', (tester) async {
      await _pumpStock(tester, entry.$2, _loadedStore());

      expect(find.byType(ErrorBanner), findsNothing);
      expect(find.text('Portland Cement'), findsOneWidget);

      await expectLater(
        find.byKey(pageKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/k4-stock-list-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }

  testWidgets('stock empty at 760 px', (tester) async {
    // Loaded, nothing in the catalogue: the only state allowed to say "no rows".
    await _pumpStock(tester, const Size(760, 900), _emptyStore());

    expect(find.text('No stock records match these filters.'), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/k4-stock-empty-760.png')),
    );
  }, skip: !enabled);

  testWidgets('stock error at 760 px', (tester) async {
    await _pumpStock(tester, const Size(760, 900), _failedStore());

    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(find.text('Cannot connect to the BuildPro server.'), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/k4-stock-error-760.png')),
    );
  }, skip: !enabled);
}

const pageKey = ValueKey('InventoryStockPageGolden');

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

Future<void> _pumpStock(
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
          ChangeNotifierProvider<AuthViewmodel>(
            create: (_) => AuthViewmodel(AuthRepository(AuthService())),
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
          home: const InventoryStockPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// A whole stock book: a long product name, a seven digit quantity, one low and
/// one out of stock row, and shelf notes on the device.
InventoryViewmodel _loadedStore() {
  final products = [
    product(
      id: 1,
      name: 'Portland Cement',
      categoryName: 'Cement',
      variants: [
        variant(
          id: 1,
          productId: 1,
          name: '40 kg bag',
          threshold: 30,
          baseUomCode: 'BAG',
          sellingUoms: [
            variantUom(id: 1, variantId: 1, uomCode: 'BAG', barcode: '4801234'),
          ],
        ),
      ],
    ),
    product(
      id: 2,
      name: 'Deformed Steel Bar 10 mm x 6 m Grade 60',
      categoryName: 'Steel bars',
      variants: [
        variant(
          id: 2,
          productId: 2,
          name: '10 mm x 6 m',
          threshold: 80,
          baseUomCode: 'PC',
          sellingUoms: [
            variantUom(id: 2, variantId: 2, uomCode: 'PC', barcode: '4805678'),
          ],
        ),
      ],
    ),
    product(
      id: 3,
      name: 'Fill Sand',
      categoryName: 'Aggregates',
      variants: [
        variant(
          id: 3,
          productId: 3,
          name: 'Screened',
          threshold: 500,
          baseUomCode: 'CU.M',
        ),
      ],
    ),
    product(
      id: 4,
      name: 'Marine Plywood 3/4 in',
      categoryName: 'Plywood',
      variants: [
        variant(
          id: 4,
          productId: 4,
          name: '4 ft x 8 ft',
          threshold: 12,
          baseUomCode: 'SHT',
        ),
      ],
    ),
    product(
      id: 5,
      name: 'Latex Paint White 4 L',
      categoryName: 'Paint',
      variants: [
        variant(
          id: 5,
          productId: 5,
          name: 'Glossy',
          threshold: 10,
          baseUomCode: 'CAN',
        ),
      ],
    ),
  ];

  SharedPreferences.setMockInitialValues({
    'stock_location_hints': jsonEncode({'1': 'Shelf G-02', '3': 'Yard E-02'}),
  });

  final batches = [
    batch(id: 1, variantId: 1, qty: 130),
    batch(id: 2, variantId: 2, qty: 64),
    // Seven digits, so the numeric column has to group thousands.
    batch(id: 3, variantId: 3, qty: 1234567),
    batch(id: 4, variantId: 4, qty: 18),
    // No batch for variant 5: nothing on hand.
  ];

  return InventoryViewmodel.seeded(
    products: products,
    batches: batches,
    stockOnHand: onHandFromBatches(batches),
    categories: [
      category(id: 1, name: 'Cement'),
      category(id: 2, name: 'Steel bars'),
      category(id: 3, name: 'Aggregates'),
      category(id: 4, name: 'Plywood'),
      category(id: 5, name: 'Paint'),
    ],
    catalogue: FakeProductsRepository(products: products),
    inventory: FakeInventoryRepository(),
    catalogueLists: FakeCatalogueRepository(),
  )..loadLocationHints();
}

InventoryViewmodel _emptyStore() {
  SharedPreferences.setMockInitialValues({});
  return InventoryViewmodel.seeded(
    catalogue: FakeProductsRepository(),
    inventory: FakeInventoryRepository(),
    catalogueLists: FakeCatalogueRepository(),
  );
}

InventoryViewmodel _failedStore() {
  SharedPreferences.setMockInitialValues({});
  return InventoryViewmodel(
    products: _FailingProductsRepository(),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );
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
