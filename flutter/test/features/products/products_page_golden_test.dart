@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:client/features/products/views/products_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

/// Card K2's visual check (00-shared/VERIFY.md fallback 3): the real Products
/// page, real fonts, written as PNGs so the layout can be looked at without the
/// browser.
///
/// Opt in, so the normal suite never compares goldens:
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/products/products_page_golden_test.dart
/// ```
void main() {
  const enabled = bool.fromEnvironment('RUN_GOLDENS');

  // Absolute, so the PNGs land in the SDD folder shared with the other cards.
  const goldenDir =
      '/home/yaji/projects/qb_ecosystem/qb_pos_inventory_system/.superpowers/sdd/ui-refresh/goldens';

  setUpAll(() async {
    Directory(goldenDir).createSync(recursive: true);
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
    // The brand fonts stop at Latin, so the peso sign would be a box.
    for (final candidate in _pesoFontCandidates) {
      if (File(candidate).existsSync()) {
        await _loadFontFile(_pesoFallbackFamily, candidate);
        break;
      }
    }
  });

  for (final width in const [1440.0, 1100.0, 760.0]) {
    testWidgets('products table view at ${width.toInt()} px', (tester) async {
      await _pumpPage(tester, Size(width, 900));
      await _expectGolden(tester, '$goldenDir/k2-table-${width.toInt()}.png');
    }, skip: !enabled);
  }

  testWidgets('products grid view at 1100 px', (tester) async {
    await _pumpPage(tester, const Size(1100, 900));
    await tester.tap(find.byTooltip('Grid view'));
    await tester.pumpAndSettle();
    await _expectGolden(tester, '$goldenDir/k2-grid-1100.png');
  }, skip: !enabled);

  testWidgets('products empty state at 760 px', (tester) async {
    await _pumpPage(tester, const Size(760, 900), products: const []);
    await _expectGolden(tester, '$goldenDir/k2-empty-760.png');
  }, skip: !enabled);

  testWidgets('products error state at 760 px', (tester) async {
    await _pumpPage(tester, const Size(760, 900), fail: true);
    await _expectGolden(tester, '$goldenDir/k2-error-760.png');
  }, skip: !enabled);
}

const pageKey = ValueKey('ProductsPageGolden');
const String _pesoFallbackFamily = 'PesoFallback';

const List<String> _pesoFontCandidates = [
  '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
  '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
  '/usr/share/fonts/TTF/DejaVuSans.ttf',
  '/System/Library/Fonts/Supplemental/Arial.ttf',
  'C:/Windows/Fonts/arial.ttf',
];

/// Refuses the catalogue the way an unreachable server does, so the page shows
/// its error banner instead of rows.
class _FailingProductsRepository extends ProductsRepository {
  _FailingProductsRepository() : super(ProductsService());

  @override
  Future<ProductsSnapshot> loadCatalogue() async =>
      throw const ProductsServiceException('Cannot connect.');
}

/// A catalogue with the awkward values the card asks for: a long name, a long
/// category and brand, a 7 digit price, and every stock state.
List<Product> _catalogue() => [
  product(
    id: 1,
    name: 'Portland Cement 40 kg bag, type 1P, pallet of 40 bags',
    categoryName: 'Cement and Aggregates',
    brandName: 'Holcim Philippines Incorporated',
    variants: [
      variant(
        id: 11,
        productId: 1,
        name: '40 kg bag',
        sellingUoms: [
          variantUom(
            id: 111,
            variantId: 11,
            price: 1234567.89,
            barcode: 'QB000011-2',
            uomCode: 'BAG',
          ),
        ],
      ),
    ],
  ),
  product(
    id: 2,
    name: 'Deformed Steel Bar 10 mm',
    categoryName: 'Steel bars',
    brandName: 'Steel Asia',
    variants: [
      variant(
        id: 22,
        productId: 2,
        name: '6 m length',
        threshold: 5,
        sellingUoms: [
          variantUom(
            id: 222,
            variantId: 22,
            price: 315,
            barcode: 'QB000022-3',
            uomCode: 'PC',
          ),
        ],
      ),
    ],
  ),
  product(
    id: 3,
    name: 'Marine Plywood 3/4 in',
    categoryName: 'Plywood',
    brandName: 'Coco Board',
    variants: [
      variant(
        id: 33,
        productId: 3,
        name: '4 x 8 sheet',
        sellingUoms: [
          variantUom(
            id: 333,
            variantId: 33,
            price: 1480.5,
            barcode: 'QB000033-1',
            uomCode: 'SHT',
          ),
        ],
      ),
    ],
  ),
  product(
    id: 4,
    name: 'PVC Pipe 2 in x 3 m',
    categoryName: 'Plumbing',
    brandName: 'Neltex',
    variants: [
      variant(
        id: 44,
        productId: 4,
        name: '2 in',
        sellingUoms: [
          variantUom(
            id: 444,
            variantId: 44,
            price: 320,
            barcode: 'QB000044-2',
            uomCode: 'PC',
          ),
        ],
      ),
    ],
  ),
];

List<InventoryBatch> _batches() => [
  batch(id: 1, variantId: 11, qty: 120),
  batch(id: 2, variantId: 22, qty: 3),
  // Variants 33 and 44 have no batch: out of stock.
];

Future<void> _pumpPage(
  WidgetTester tester,
  Size size, {
  List<Product>? products,
  bool fail = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final catalogue = products ?? _catalogue();
  final store = InventoryViewmodel(
    products: fail
        ? _FailingProductsRepository()
        : FakeProductsRepository(
            products: catalogue,
            batches: catalogue.isEmpty ? const [] : _batches(),
          ),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );

  await tester.pumpWidget(
    RepaintBoundary(
      key: pageKey,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AuthViewmodel(AuthRepository(AuthService())),
          ),
          ChangeNotifierProvider<InventoryViewmodel>.value(value: store),
          ChangeNotifierProvider(create: (_) => ProductTrackingViewmodel()),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme.copyWith(
            // Only the golden: lets the peso sign fall back to the system font
            // the app itself uses, because the brand fonts stop at Latin.
            textTheme: AppTheme.lightTheme.textTheme.apply(
              fontFamilyFallback: const [_pesoFallbackFamily],
            ),
          ),
          home: const ProductsPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _expectGolden(WidgetTester tester, String path) async {
  await expectLater(find.byKey(pageKey), matchesGoldenFile(Uri.file(path)));
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
