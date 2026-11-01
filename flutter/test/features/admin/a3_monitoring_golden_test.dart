@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/features/admin/views/inventory_monitoring_page.dart';
import 'package:client/features/admin/views/sales_monitoring_page.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/shared/widgets/filter_bar.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

/// The fallback visual check (00-shared/VERIFY.md, fallback 3) for card A3: the
/// admin Inventory monitoring and Sales & POS monitoring screens, rendered with
/// the REAL fonts and the REAL theme, inside their real admin shell, into the
/// SDD folder.
///
/// Same opt-in mechanism as F3's gallery, so the normal suite never fails on a
/// font or platform difference.
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/admin/a3_monitoring_golden_test.dart
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
    // The bundled brand fonts stop at Latin, so a peso sign needs a system font
    // that carries it, or every money figure paints as a tofu box.
    for (final candidate in _pesoFontCandidates) {
      if (File(candidate).existsSync()) {
        await _loadFontFile(_pesoFallbackFamily, candidate);
        break;
      }
    }
  });

  group('inventory monitoring', () {
    for (final entry in const [
      ('1440', Size(1440, 900)),
      ('1100', Size(1100, 900)),
      ('760', Size(760, 900)),
    ]) {
      testWidgets('loaded at ${entry.$1} px', (tester) async {
        await _pump(
          tester,
          entry.$2,
          InventoryMonitoringPage(repository: _ValuationStub(_valuation)),
        );
        await _shoot(
          tester,
          goldenDir,
          'a3-inventory-monitoring-loaded-'
          '${entry.$1}.png',
        );
      }, skip: !enabled);
    }

    testWidgets('empty at 760 px', (tester) async {
      await _pump(
        tester,
        const Size(760, 900),
        InventoryMonitoringPage(
          repository: _ValuationStub(
            const InventoryValuation(
              batchCount: 0,
              totalUnits: 0,
              totalCost: 0,
              totalRetail: 0,
              categories: [],
            ),
          ),
        ),
        inventory: _emptyStock(),
      );
      await _shoot(tester, goldenDir, 'a3-inventory-monitoring-empty-760.png');
    }, skip: !enabled);

    testWidgets('error at 760 px', (tester) async {
      await _pump(
        tester,
        const Size(760, 900),
        InventoryMonitoringPage(
          repository: _ValuationStub(
            _valuation,
            failure: 'The inventory valuation could not be loaded.',
          ),
        ),
        inventory: _failingStock(),
      );
      await _shoot(tester, goldenDir, 'a3-inventory-monitoring-error-760.png');
    }, skip: !enabled);
  });

  group('sales monitoring', () {
    for (final entry in const [
      ('1440', Size(1440, 900)),
      ('1100', Size(1100, 900)),
      ('760', Size(760, 900)),
    ]) {
      testWidgets('loaded at ${entry.$1} px', (tester) async {
        await _pump(
          tester,
          entry.$2,
          SalesMonitoringPage(
            repository: _ValuationStub.summary(_monthOfSales),
          ),
        );
        await _shoot(
          tester,
          goldenDir,
          'a3-sales-monitoring-loaded-'
          '${entry.$1}.png',
        );
      }, skip: !enabled);
    }

    // The widest chip over a month of trading: the shot that proves the label
    // thinning and the narrower bars a real branch sees.
    for (final entry in const [
      ('1100', Size(1100, 900)),
      ('760', Size(760, 900)),
    ]) {
      testWidgets('a month at ${entry.$1} px', (tester) async {
        await _pump(
          tester,
          entry.$2,
          SalesMonitoringPage(
            repository: _ValuationStub.summary(_monthOfSales),
          ),
        );
        await tester.tap(
          find.descendant(
            of: find.byType(FilterBar),
            matching: find.text('Last 30 days'),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '30 labels in one bar row must thin, not overlap',
        );
        await _shoot(
          tester,
          goldenDir,
          'a3-sales-monitoring-month-'
          '${entry.$1}.png',
        );
      }, skip: !enabled);
    }

    testWidgets('empty at 760 px', (tester) async {
      await _pump(
        tester,
        const Size(760, 900),
        SalesMonitoringPage(repository: _ValuationStub.summary(_noSales)),
        inventory: _emptyStock(),
      );
      await _shoot(tester, goldenDir, 'a3-sales-monitoring-empty-760.png');
    }, skip: !enabled);

    testWidgets('error at 760 px', (tester) async {
      await _pump(
        tester,
        const Size(760, 900),
        SalesMonitoringPage(
          repository: _ValuationStub.summary(
            _monthOfSales,
            failure: 'The sales summary could not be loaded.',
          ),
        ),
        inventory: _emptyStock(),
      );
      await _shoot(tester, goldenDir, 'a3-sales-monitoring-error-760.png');
    }, skip: !enabled);
  });
}

const _goldenKey = ValueKey('MonitoringGolden');

Future<void> _pump(
  WidgetTester tester,
  Size size,
  Widget page, {
  InventoryViewmodel? inventory,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewmodel>.value(
          value: AuthViewmodel(AuthRepository(AuthService())),
        ),
        ChangeNotifierProvider<InventoryViewmodel>.value(
          value: inventory ?? _stock(),
        ),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme.copyWith(
          // Only the goldens: lets a peso sign fall back to the system font the
          // app itself uses, because the brand fonts stop at Latin.
          textTheme: AppTheme.lightTheme.textTheme.apply(
            fontFamilyFallback: const [_pesoFallbackFamily],
          ),
        ),
        home: RepaintBoundary(
          key: _goldenKey,
          child: ColoredBox(
            color: AppTheme.lightTheme.colorScheme.surface,
            child: page,
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

Future<void> _shoot(WidgetTester tester, Directory dir, String name) {
  return expectLater(
    find.byKey(_goldenKey),
    matchesGoldenFile(Uri.file('${dir.path}/$name')),
  );
}

/// Answers either report from memory; no PNG depends on a server.
class _ValuationStub extends ReportsRepository {
  _ValuationStub(this.valuation, {this.failure});

  _ValuationStub.summary(this.summary, {this.failure})
    : valuation = const InventoryValuation(
        batchCount: 0,
        totalUnits: 0,
        totalCost: 0,
        totalRetail: 0,
        categories: [],
      );

  final InventoryValuation valuation;
  SalesSummary summary = _noSales;
  final String? failure;

  @override
  Future<InventoryValuation> fetchInventoryValuation() async {
    final failure = this.failure;
    if (failure != null) throw ReportsServiceException(failure);
    return valuation;
  }

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
    final failure = this.failure;
    if (failure != null) throw ReportsServiceException(failure);
    return summary;
  }
}

/// A month of trading for a branch that also sells to builders: totals land in
/// seven figures, so a money column or tile that clips shows up in the PNG.
final SalesSummary _monthOfSales = _salesSummary(days: 30);

final SalesSummary _noSales = const SalesSummary(
  from: '2026-10-01',
  to: '2026-10-30',
  totalTransactions: 0,
  totalGross: 0,
  totalVat: 0,
  totalDiscounts: 0,
  days: [],
);

SalesSummary _salesSummary({required int days}) {
  final today = appClock.now();
  final rows = <SalesDay>[];
  var gross = 0.0;
  var transactions = 0;
  for (var back = days - 1; back >= 0; back--) {
    final day = today.subtract(Duration(days: back));
    // A believable week: busier Mondays, a quiet Sunday, one big delivery day.
    final weekday = day.weekday;
    final daily = weekday == DateTime.sunday
        ? 42000.0
        : 96000.0 + (back % 5) * 21500.0;
    final count = weekday == DateTime.sunday ? 6 : 11 + (back % 7);
    gross += daily;
    transactions += count;
    rows.add(
      SalesDay(
        day:
            '${day.year.toString().padLeft(4, '0')}-'
            '${day.month.toString().padLeft(2, '0')}-'
            '${day.day.toString().padLeft(2, '0')}',
        transactions: count,
        gross: daily,
        vat: daily / 1.12 * 0.12,
        discounts: 0,
      ),
    );
  }
  return SalesSummary(
    from: rows.first.day,
    to: rows.last.day,
    totalTransactions: transactions,
    totalGross: gross,
    totalVat: 0,
    totalDiscounts: 0,
    days: rows,
  );
}

/// The server's stock valuation: seven-figure money, so a clipped peso amount
/// shows in the PNG.
const _valuation = InventoryValuation(
  batchCount: 137,
  totalUnits: 12480,
  totalCost: 1234567.89,
  totalRetail: 1780000,
  categories: [],
);

/// A working store's stock book: four variants with nothing left, five under
/// their own level, the rest healthy. Two long names, so no row can hide what
/// matters by shortening.
InventoryViewmodel _stock() {
  SharedPreferences.setMockInitialValues({});
  final products = _products();
  final batches = _batches();
  return InventoryViewmodel.seeded(
    products: products,
    batches: batches,
    alerts: const [],
    catalogue: FakeProductsRepository(products: products, batches: batches),
    inventory: FakeInventoryRepository(),
    catalogueLists: FakeCatalogueRepository(),
  );
}

/// Nothing has been bought yet: the state on the day a branch is opened.
InventoryViewmodel _emptyStock() {
  SharedPreferences.setMockInitialValues({});
  return InventoryViewmodel.seeded(
    catalogue: FakeProductsRepository(),
    inventory: FakeInventoryRepository(),
    catalogueLists: FakeCatalogueRepository(),
  );
}

/// The catalogue read fails, so the page has no stock to claim and shows one
/// banner instead of tiles full of zeroes.
InventoryViewmodel _failingStock() {
  SharedPreferences.setMockInitialValues({});
  return InventoryViewmodel(
    products: _DeadCatalogue(),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );
}

class _DeadCatalogue extends FakeProductsRepository {
  @override
  Future<ProductsSnapshot> loadCatalogue() async =>
      throw const ProductsServiceException(
        'Cannot connect to the BuildPro server.',
      );
}

List<Product> _products() {
  return <Product>[
    _product(1, 'Marine Plywood 3/4 in x 4 ft x 8 ft', '3/4 in', 20),
    _product(2, 'Portland Cement', '40 kg bag', 30),
    _product(3, 'Deformed Steel Bar 10 mm x 6 m', '10 mm', 40),
    _product(4, 'Common Nails', '2 in', 15),
    _product(5, 'Ordinary Plywood 1/4 in x 4 ft x 8 ft', '1/4 in', 18),
    _product(6, 'PVC Pipe Series 1000', '2 in x 3 m', 25),
    _product(7, 'Latex Paint, Semi Gloss, White', '4 L', 12),
    _product(8, 'Fill Sand', 'Screened', 5),
    _product(9, 'Hollow Blocks', '4 in', 200),
    _product(10, 'Galvanized Iron Sheet', '8 ft', 60),
    _product(11, 'Electrical Wire THHN', '3.5 mm x 150 m', 8),
    _product(12, 'Water Closet, Two Piece', 'White', 6),
  ];
}

Product _product(int id, String name, String variantName, double threshold) {
  return product(
    id: id,
    name: name,
    variants: [
      variant(id: id, productId: id, name: variantName, threshold: threshold),
    ],
  );
}

List<InventoryBatch> _batches() {
  return <InventoryBatch>[
    // Nothing left: the rows an owner acts on first.
    batch(id: 1, variantId: 1, qty: 0, cost: 640),
    batch(id: 2, variantId: 8, qty: 0, cost: 420),
    batch(id: 3, variantId: 11, qty: 0, cost: 4850),
    batch(id: 4, variantId: 4, qty: 0, cost: 62),
    // Under their own level.
    batch(id: 5, variantId: 2, qty: 12, cost: 180),
    batch(id: 6, variantId: 5, qty: 9, cost: 512),
    batch(id: 7, variantId: 6, qty: 14, cost: 385),
    batch(id: 8, variantId: 7, qty: 3, cost: 1240),
    batch(id: 9, variantId: 12, qty: 2, cost: 3650),
    // Healthy, and worth the most at landed cost.
    batch(id: 10, variantId: 3, qty: 640, cost: 285),
    batch(id: 11, variantId: 9, qty: 4800, cost: 26.5),
    batch(id: 12, variantId: 10, qty: 320, cost: 468),
    batch(id: 13, variantId: 6, qty: 210, cost: 385),
  ];
}

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
