@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/constants/app_assets.dart';
import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/ledger_entry.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/ledger_repository.dart';
import 'package:client/data/repositories/reports_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/ledger_service.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/sales/viewmodels/inventory_sales_viewmodel.dart';
import 'package:client/features/sales/viewmodels/sales_dashboard_alerts_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/sales/views/sales_dashboard_page.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:client/core/time/app_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';
import '../../support/transactions_fixtures.dart';

/// The fallback visual check for card M1 (00-shared/VERIFY.md, fallback 3): the
/// real Store Manager dashboard inside its real shell, painted with the real
/// fonts and written as PNGs into the SDD folder so the layout can be looked at
/// without a browser.
///
/// Opt in, so a font or platform difference never fails the normal suite:
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/sales/sales_dashboard_golden_test.dart
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
    if (icons != null) await _loadFontFile('MaterialIcons', icons);
    // The bundled brand fonts stop at Latin, so a peso sign needs a system font
    // that carries it.
    for (final candidate in _pesoFontCandidates) {
      if (File(candidate).existsSync()) {
        await _loadFontFile(_pesoFallbackFamily, candidate);
        break;
      }
    }
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final entry in const [
    ('1440', Size(1440, 900)),
    ('1100', Size(1100, 900)),
    ('760', Size(760, 900)),
  ]) {
    testWidgets('m1 dashboard at ${entry.$1} px', (tester) async {
      await _pump(tester, entry.$2, _loaded());

      expect(find.byType(ErrorBanner), findsNothing);
      // What needs the manager, then the numbers, all on screen.
      expect(find.text('Needs you'), findsOneWidget);
      expect(find.text('Overdue receivables'), findsOneWidget);
      expect(find.text('Returns today'), findsOneWidget);
      // Seven digits, so the money grouping is tested on a real width.
      expect(find.text('₱1,234,865.50'), findsOneWidget);
      // One heading, and it is not the shell's.
      expect(find.text('Sales overview'), findsNothing);

      await expectLater(
        find.byKey(pageKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/m1-loaded-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }

  testWidgets('m1 dashboard empty at 760 px', (tester) async {
    await _pump(tester, const Size(760, 900), _empty());

    // Nothing loaded is said in words, and no count is invented: the queue
    // tiles show zeros because their reads answered with nothing.
    expect(find.text('No sales transactions yet.'), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/m1-empty-760.png')),
    );
  }, skip: !enabled);

  testWidgets('m1 dashboard error at 760 px', (tester) async {
    await _pump(tester, const Size(760, 900), _failed());

    // One failure surface with one retry, and a tile that could not be
    // counted says so instead of showing a zero.
    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(
      find.text('The sales list could not be loaded. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Not loaded'), findsWidgets);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/m1-error-760.png')),
    );
  }, skip: !enabled);
}

const pageKey = ValueKey('SalesDashboardGolden');

// ---------------------------------------------------------------- fixtures

/// A branch's Tuesday: five recorded sales, two returns earlier today, a
/// seven-digit day, one very long customer name.
List<TransactionRecord> _transactions() {
  final now = appClock.now();
  return [
    ...transactionsFixture(),
    _return(
      id: 21,
      no: 'TRX-20261030-0011',
      at: DateTime(now.year, now.month, now.day, 9, 12),
      total: -1480,
    ),
    _return(
      id: 22,
      no: 'TRX-20261030-0012',
      at: DateTime(now.year, now.month, now.day, 10, 5),
      total: -320,
    ),
  ];
}

TransactionRecord _return({
  required int id,
  required String no,
  required DateTime at,
  required double total,
}) => TransactionRecord(
  id: id,
  transactionNo: no,
  transDate: at,
  customerId: 3,
  customerName: 'Walk-in customer',
  cashierName: 'Ana Reyes',
  source: 'RETURN',
  originalTransactionId: 1,
  status: 'REFUNDED',
  grandTotal: total,
  items: const [
    TransactionLineItem(
      variantUomId: 42,
      variantUomCode: 'CEM-40KG',
      qty: 2,
      unitPrice: 740,
      subtotal: 1480,
    ),
  ],
  payments: const [],
);

/// Two receivables already past due. The requisition queue that used to be
/// counted here is gone (decision 01: CPMS approves).
SalesDashboardAlertsViewmodel _queues({int overdue = 2, bool failing = false}) =>
    SalesDashboardAlertsViewmodel(
      ledgers: failing
          ? _FailingLedgers()
          : _StubLedgers(
              rows: [
                for (var i = 1; i <= overdue; i++)
                  LedgerEntry(
                    id: i,
                    customerId: i,
                    customerName: 'Customer $i',
                    transactionNo: 'TRX-20261030-000$i',
                    originalAmount: 48000,
                    balanceDue: 24000,
                    dueDate: DateTime(2026, 9, 30),
                    isOverdue: true,
                  ),
              ],
            ),
    );

/// The catalogue the four fixture selling units belong to, named the way the
/// products screen names them.
InventoryViewmodel _catalogue() {
  final inventory = InventoryViewmodel(
    products: FakeProductsRepository(
      products: [
        product(
          id: 1,
          name: 'Portland Cement',
          categoryName: 'Cement',
          brandName: 'Holcim',
          variants: [
            variant(
              id: 1,
              productId: 1,
              name: '40 kg bag',
              sellingUoms: [
                variantUom(id: 42, variantId: 1, price: 260, uomCode: 'BAG'),
              ],
            ),
          ],
        ),
        product(
          id: 2,
          name: 'PVC Pipe',
          categoryName: 'Plumbing',
          brandName: 'Neltex',
          variants: [
            variant(
              id: 2,
              productId: 2,
              name: '2 inch',
              sellingUoms: [
                variantUom(id: 43, variantId: 2, price: 240, uomCode: 'PC'),
              ],
            ),
          ],
        ),
        product(
          id: 3,
          name: 'Ceramic Tile',
          categoryName: 'Finishing',
          brandName: 'Mariwasa',
          variants: [
            variant(
              id: 3,
              productId: 3,
              name: '60 x 60',
              sellingUoms: [
                variantUom(id: 44, variantId: 3, price: 320, uomCode: 'PC'),
              ],
            ),
          ],
        ),
      ],
      batches: [
        batch(id: 1, variantId: 1, qty: 100),
        batch(id: 2, variantId: 2, qty: 100),
        batch(id: 3, variantId: 3, qty: 100),
      ],
    ),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );
  return inventory..load();
}

({InventorySalesViewmodel sales, SalesDashboardAlertsViewmodel alerts})
_loaded() => (
  sales: InventorySalesViewmodel(
    service: StubSalesService(rows: _transactions()),
    reports: _SummaryRepository(totalGross: 1234865.50, totalTransactions: 26),
  ),
  alerts: _queues(),
);

({InventorySalesViewmodel sales, SalesDashboardAlertsViewmodel alerts})
_empty() => (
  sales: InventorySalesViewmodel(
    service: StubSalesService(),
    reports: _SummaryRepository(totalGross: 0, totalTransactions: 0),
  ),
  alerts: _queues(overdue: 0),
);

({InventorySalesViewmodel sales, SalesDashboardAlertsViewmodel alerts})
_failed() => (
  sales: InventorySalesViewmodel(
    service: StubSalesService(
      error: 'The sales list could not be loaded. Try again.',
    ),
    reports: _FailingReports(),
  ),
  alerts: _queues(failing: true),
);

class _SummaryRepository extends ReportsRepository {
  _SummaryRepository({
    required this.totalGross,
    required this.totalTransactions,
  }) : super();

  final double totalGross;
  final int totalTransactions;

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async =>
      SalesSummary(
        from: '2026-10-01',
        to: '2026-10-30',
        totalTransactions: totalTransactions,
        totalGross: totalGross,
        totalVat: 0,
        totalDiscounts: 0,
        days: const [],
      );
}

class _FailingReports extends ReportsRepository {
  _FailingReports() : super();

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async =>
      throw const ReportsServiceException('Summary unavailable.');
}

class _StubLedgers extends LedgerRepository {
  _StubLedgers({required this.rows}) : super();

  final List<LedgerEntry> rows;

  @override
  Future<List<LedgerEntry>> fetchLedgers() async => rows;
}

class _FailingLedgers extends LedgerRepository {
  _FailingLedgers() : super();

  @override
  Future<List<LedgerEntry>> fetchLedgers() async =>
      throw const LedgerServiceException(
        'The receivables list could not be loaded. Try again.',
      );
}

// ---------------------------------------------------------------- harness

Future<void> _pump(
  WidgetTester tester,
  Size size,
  ({InventorySalesViewmodel sales, SalesDashboardAlertsViewmodel alerts})
  stores,
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
            value: AuthViewmodel(AuthRepository(AuthService())),
          ),
          ChangeNotifierProvider<InventorySalesViewmodel>.value(
            value: stores.sales,
          ),
          // FX4: the sales wire carries the selling unit's id and code, so the
          // top-products panel can only print a NAME when the app-scoped
          // catalogue (which the dashboard reads) has been loaded. The PNG is
          // the visual proof that it does.
          ChangeNotifierProvider<InventoryViewmodel>.value(value: _catalogue()),
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
          home: SalesDashboardPage(viewmodel: stores.alerts),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // The logo is an asset image and image decoding does not run inside the fake
  // async zone: without this the brand renders as empty space.
  await tester.runAsync(() async {
    final context = tester.element(find.byKey(pageKey));
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
  expect(
    tester.takeException(),
    isNull,
    reason: 'a layout overflow would paint the yellow stripes into the PNG',
  );
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
