@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_stock_movements_page.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

/// The visual check for K5 (00-shared/VERIFY.md, fallback 3): the real Stock
/// adjustments page, inside its real Stock Manager shell, painted with the real
/// fonts and written as PNGs into the SDD folder.
///
/// Opt in, so a font or platform difference never fails the normal suite:
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/inventory/inventory_adjustments_golden_test.dart
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
    testWidgets('adjustments list at ${entry.$1} px', (tester) async {
      final store = await _pumpPage(tester, entry.$2, _loadedStore());

      expect(find.byType(ErrorBanner), findsNothing);
      expect(find.text('Damaged'), findsWidgets);
      expect(store.adjustments, hasLength(6));

      await expectLater(
        find.byKey(pageKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/k5-adjustments-list-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }

  testWidgets('adjustments empty at 760 px', (tester) async {
    await _pumpPage(tester, const Size(760, 900), _emptyStore());

    expect(
      find.text('No adjustments recorded for this period.'),
      findsOneWidget,
    );

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(
        Uri.file('${goldenDir.path}/k5-adjustments-empty-760.png'),
      ),
    );
  }, skip: !enabled);

  testWidgets('adjustments error at 760 px', (tester) async {
    await _pumpPage(tester, const Size(760, 900), _failedStore());

    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(find.text('Cannot connect to the BuildPro server.'), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(
        Uri.file('${goldenDir.path}/k5-adjustments-error-760.png'),
      ),
    );
  }, skip: !enabled);
}

const pageKey = ValueKey('InventoryStockAdjustmentsPageGolden');

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

Future<InventoryViewmodel> _pumpPage(
  WidgetTester tester,
  Size size,
  InventoryViewmodel store,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await store.load();

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
          home: const InventoryStockMovementsPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

/// A believable adjustment log: a long product name, every adjustment type, a
/// seven digit quantity, one row by another user, and one single digit quantity.
///
/// The dates hang off the start of the CURRENT month, so every row is inside the
/// page's default "This Month" period whatever day the goldens are generated.
InventoryViewmodel _loadedStore() {
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1, 9, 20);
  DateTime on(int day, [int hour = 9, int minute = 20]) => monthStart.add(
    Duration(days: day - 1, hours: hour - 9, minutes: minute - 20),
  );

  return _store(
    adjustments: [
      StockAdjustment(
        id: 41,
        variantId: 2,
        userId: 4,
        adjustmentType: StockAdjustmentType.damage,
        quantityAdjusted: -3,
        remarks: 'Bent in the yard, two cut ends.',
        timestamp: on(16, 15, 5),
      ),
      StockAdjustment(
        id: 40,
        variantId: 1,
        userId: 7,
        adjustmentType: StockAdjustmentType.correction,
        quantityAdjusted: 1234567,
        remarks: 'Annual count correction at the warehouse.',
        timestamp: on(11),
      ),
      StockAdjustment(
        id: 39,
        variantId: 3,
        userId: 4,
        adjustmentType: StockAdjustmentType.shrinkage,
        quantityAdjusted: -0.5,
        remarks: 'Spillage while loading the truck.',
        timestamp: on(7, 14, 0),
      ),
      StockAdjustment(
        id: 38,
        variantId: 1,
        userId: 9,
        adjustmentType: StockAdjustmentType.returnToSupplier,
        quantityAdjusted: -12,
        remarks: 'Returned to Holcim, damp bags.',
        timestamp: on(4),
      ),
      StockAdjustment(
        id: 37,
        variantId: 4,
        userId: 4,
        adjustmentType: StockAdjustmentType.damage,
        quantityAdjusted: -1,
        remarks: 'Cracked sheet found during the morning check.',
        timestamp: on(2, 8, 0),
      ),
      StockAdjustment(
        id: 36,
        variantId: 5,
        userId: 7,
        adjustmentType: StockAdjustmentType.correction,
        quantityAdjusted: 2,
        remarks: 'No reason given',
        timestamp: on(1, 16, 45),
      ),
    ],
  );
}

InventoryViewmodel _store({List<StockAdjustment> adjustments = const []}) {
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

  return InventoryViewmodel(
    products: FakeProductsRepository(products: products),
    inventory: FakeInventoryRepository(adjustments: adjustments),
    catalogue: FakeCatalogueRepository(),
  );
}

InventoryViewmodel _emptyStore() => _store();

InventoryViewmodel _failedStore() => InventoryViewmodel(
  products: _FailingProductsRepository(),
  inventory: FakeInventoryRepository(),
  catalogue: FakeCatalogueRepository(),
);

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
