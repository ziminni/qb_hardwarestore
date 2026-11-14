@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_colors.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/catalogue_option.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/products/widgets/products_details_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

/// Owner review material for Task 9 (phase 1d): the redesigned product details
/// dialog with real packaging units, rendered with the REAL fonts.
///
/// The plan's acceptance pair: a wide/normal capture and the narrow one at 1.3x
/// text, where clipping would show first.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/products/products_details_golden_test.dart
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

  for (final (width, scale) in const [(1440.0, 1.0), (760.0, 1.3)]) {
    testWidgets('product details at ${width.toInt()} px, text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final product = _packedProduct();
      final batches = [batch(id: 1, variantId: 210, qty: 130)];
      final inventory = InventoryViewmodel.seeded(
        catalogue: FakeProductsRepository(
          products: [product],
          batches: batches,
        ),
        inventory: FakeInventoryRepository(),
        catalogueLists: FakeCatalogueRepository(units: _units),
        products: [product],
        batches: batches,
        stockOnHand: onHandFromBatches(batches),
        units: _units,
      );
      SharedPreferences.setMockInitialValues({
        'stock_location_hints': '{"210":"Rack A-01"}',
      });
      await inventory.loadLocationHints();
      final auth = AuthViewmodel(AuthRepository(AuthService()));
      auth.user = User(
        id: 1,
        username: 'ana',
        email: 'ana@example.com',
        fullName: 'Ana Cruz',
        role: Role(id: 1, name: 'inventory', displayName: 'inventory'),
      );

      await tester.pumpWidget(
        RepaintBoundary(
          key: goldenKey,
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<InventoryViewmodel>.value(
                value: inventory,
              ),
              ChangeNotifierProvider<AuthViewmodel>.value(value: auth),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightTheme.copyWith(
                textTheme: AppTheme.lightTheme.textTheme.apply(
                  fontFamilyFallback: const [_pesoFallbackFamily],
                ),
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const _DetailsHost(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile(
          Uri.file(
            '${goldenDir.path}/f3_product_details_${width.toInt()}_'
            '${scale.toStringAsFixed(1).replaceAll('.', '_')}.png',
          ),
        ),
      );
    }, skip: !enabled);
  }
}

const goldenKey = ValueKey('ProductDetailsGolden');

/// CE-MENT: sold by the kilogram, the bag of 40 and the unused box of 10.
Product _packedProduct() => product(
  id: 21,
  name: 'Tile Adhesive',
  categoryName: 'Cement and Aggregates',
  brandName: 'ABC Construction Supply',
  variants: [
    variant(
      id: 210,
      productId: 21,
      name: 'Standard 25 kg',
      baseUomId: 2,
      baseUomCode: 'KG',
      sellingUoms: [
        variantUom(
          id: 2101,
          variantId: 210,
          uomId: 2,
          uomCode: 'KG',
          uomName: 'Kilogram',
          price: 6.75,
        ),
        variantUom(
          id: 2102,
          variantId: 210,
          uomId: 3,
          uomCode: 'BAG',
          uomName: 'Bag',
          factor: 25,
          price: 168.75,
          barcode: 'QB000210-2',
          isWhole: true,
          inUse: true,
        ),
        variantUom(
          id: 2103,
          variantId: 210,
          uomId: 4,
          uomCode: 'BOX',
          uomName: 'Box',
          factor: 10,
          price: 67.5,
          barcode: 'QB000210-3',
          isWhole: true,
        ),
      ],
    ),
  ],
);

class _DetailsHost extends StatelessWidget {
  const _DetailsHost();

  @override
  Widget build(BuildContext context) {
    return const _DialogOpener();
  }
}

class _DialogOpener extends StatefulWidget {
  const _DialogOpener();

  @override
  State<_DialogOpener> createState() => _DialogOpenerState();
}

class _DialogOpenerState extends State<_DialogOpener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog<void>(
        context: context,
        builder: (_) => ProductsDetailsDialog(product: _packedProduct()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(backgroundColor: AppColors.background);
  }
}

const _units = [
  UnitOfMeasure(id: 2, code: 'KG', name: 'Kilogram'),
  UnitOfMeasure(id: 3, code: 'BAG', name: 'Bag', isWhole: true),
  UnitOfMeasure(id: 4, code: 'BOX', name: 'Box', isWhole: true),
  UnitOfMeasure(id: 5, code: 'PACK', name: 'Pack', isWhole: true),
];

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
