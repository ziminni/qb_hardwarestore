@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/reports.dart';
import 'package:client/data/models/requisition.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/sale_transaction.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/repositories/requisition_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/reports_service.dart';
import 'package:client/data/services/sales_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/dashboard/viewmodels/admin_overview_viewmodel.dart';
import 'package:client/features/dashboard/views/admin_dashboard.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

/// The fallback visual check for A1 (00-shared/VERIFY.md, fallback 3): the real
/// Admin overview inside its real shell, painted with the real fonts and written
/// as PNGs into the SDD folder so the layout can be looked at without a browser.
///
/// Opt in, so a font or platform difference never fails the normal suite:
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/admin/admin_dashboard_golden_test.dart
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
    // that carries it.
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
    testWidgets('a1 overview at ${entry.$1} px', (tester) async {
      await _pumpOverview(tester, entry.$2);

      expect(find.byType(ErrorBanner), findsNothing);
      expect(find.text('Needs attention'), findsOneWidget);
      // Seven digits in the tiles and a long customer name in the table, so
      // grouping and ellipsis are both exercised.
      expect(find.text('₱1,234,865.00'), findsWidgets);
      expect(
        find.textContaining('Dela Cruz Construction and Development'),
        findsOneWidget,
      );

      await expectLater(
        find.byKey(pageKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/a1-loaded-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }

  testWidgets('a1 overview empty at 760 px', (tester) async {
    await _pumpOverview(tester, const Size(760, 900), empty: true);

    // A loaded day with nothing in it: zeroes are the truth here, unlike a
    // failed read.
    expect(find.text('No sales recorded yet.'), findsOneWidget);
    expect(find.text('No active alerts.'), findsOneWidget);
    expect(find.text('₱0.00'), findsWidgets);
    expect(find.textContaining('1,234,865'), findsNothing);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/a1-empty-760.png')),
    );
  }, skip: !enabled);

  testWidgets('a1 overview error at 760 px', (tester) async {
    await _pumpOverview(tester, const Size(760, 900), failed: true);

    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(find.text('Cannot connect to the BuildPro server.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
    // One failure, not a failure above a page of zeroes.
    expect(find.text('No sales recorded yet.'), findsNothing);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/a1-error-760.png')),
    );
  }, skip: !enabled);
}

const pageKey = ValueKey('AdminOverviewGolden');

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

Future<void> _pumpOverview(
  WidgetTester tester,
  Size size, {
  bool empty = false,
  bool failed = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final inventory = empty
      ? InventoryViewmodel(
          products: _GoldenProductsRepository(),
          inventory: _GoldenInventoryRepository(),
          catalogue: FakeCatalogueRepository(),
        )
      : InventoryViewmodel(
          products: _GoldenProductsRepository(
            products: _products,
            batches: _batches,
          ),
          inventory: _GoldenInventoryRepository(alerts: _alerts),
          catalogue: FakeCatalogueRepository(),
        );
  await inventory.load();

  final overview = AdminOverviewViewmodel(
    reports: _GoldenReportsService(
      failure: failed ? _offline : null,
      summary: empty ? _noSales : null,
    ),
    sales: _GoldenSalesService(sales: empty || failed ? const [] : _sales),
    requisitions: _GoldenRequisitionRepository(
      requisitions: empty || failed ? const [] : _requisitions,
    ),
  );
  await overview.load();

  await tester.pumpWidget(
    RepaintBoundary(
      key: pageKey,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>.value(value: _adminAuth()),
          ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
          ChangeNotifierProvider<AdminOverviewViewmodel>.value(value: overview),
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
          home: const AdminDashboard(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const String _offline = 'Cannot connect to the BuildPro server.';

/// The admin the shell reads its name and role from.
AuthViewmodel _adminAuth() {
  final auth = AuthViewmodel(AuthRepository(AuthService()));
  auth.user = User(
    id: 1,
    username: 'admin',
    email: 'admin@qb.ph',
    fullName: 'Josefa Ramos',
    role: const Role(id: 1, name: 'admin', displayName: 'Admin'),
  );
  return auth;
}

/// A branch's catalogue: one line out of stock, two low, the rest healthy, and
/// a stock value in the millions.
final List<Product> _products = [
  _product(id: 1, name: 'Portland Cement', threshold: 50, variants: 2),
  _product(
    id: 2,
    name: 'Deformed Steel Bar 10 mm x 6 m Grade 60',
    threshold: 80,
  ),
  _product(id: 3, name: 'Tiles 60x60', threshold: 40),
  _product(id: 4, name: 'Fill Sand', threshold: 1200),
  _product(id: 5, name: 'PVC Pipe 1/2 inch', threshold: 100),
  _product(id: 6, name: 'Latex Paint White 4 L', threshold: 10),
];

final List<InventoryBatch> _batches = [
  _batch(id: 1, variantId: 1, qty: 12, cost: 240),
  _batch(id: 2, variantId: 2, qty: 0, cost: 320),
  _batch(id: 3, variantId: 3, qty: 25, cost: 375),
  // Seven digits into the value tile.
  _batch(id: 4, variantId: 4, qty: 1199000, cost: 1),
  _batch(id: 5, variantId: 5, qty: 41, cost: 95),
  _batch(id: 6, variantId: 6, qty: 9, cost: 480),
];

final List<SystemAlert> _alerts = [
  SystemAlert(
    id: 31,
    type: SystemAlertType.outOfStock,
    variantId: 2,
    message: 'Deformed Steel Bar 10 mm x 6 m Grade 60 has nothing on hand.',
    isResolved: false,
    createdAt: DateTime(2026, 10, 29, 8, 10),
  ),
  SystemAlert(
    id: 30,
    type: SystemAlertType.lowStock,
    variantId: 1,
    message: 'Portland Cement 40kg is down to 12 bags, under its 50 bag level.',
    isResolved: false,
    createdAt: DateTime(2026, 10, 29, 7, 45),
  ),
  SystemAlert(
    id: 29,
    type: SystemAlertType.lowStock,
    variantId: 6,
    message: 'Latex Paint White 4 L was restocked this morning.',
    isResolved: true,
    createdAt: DateTime(2026, 10, 28, 16, 20),
  ),
];

final List<TransactionRecord> _sales = [
  _sale(
    id: 12,
    number: 'TRX-20261029-0012',
    customer: 'Dela Cruz Construction and Development Corporation',
    amount: 1234865,
    at: DateTime(2026, 10, 29, 14, 40),
  ),
  _sale(
    id: 11,
    number: 'TRX-20261029-0011',
    customer: 'Maria Santos',
    amount: 1480,
    at: DateTime(2026, 10, 29, 13, 5),
  ),
  _sale(
    id: 10,
    number: 'TRX-20261029-0010',
    customer: 'Walk in customer',
    amount: 8600,
    at: DateTime(2026, 10, 29, 11, 32),
  ),
];

final List<Requisition> _requisitions = [
  const Requisition(
    id: 3,
    reqNumber: 'REQ-20261029-0003',
    rawStatus: 'SUBMITTED',
    projectName: 'Hillside Phase 2',
    projectCustomerName: 'Hillside Realty',
    requestedByName: 'Reyes, Mario',
    items: [],
  ),
  const Requisition(
    id: 2,
    reqNumber: 'REQ-20261029-0002',
    rawStatus: 'SUBMITTED',
    projectName: 'Cogon Bridge Repair',
    projectCustomerName: 'Cogon LGU',
    requestedByName: 'Bautista, Liza',
    items: [],
  ),
  const Requisition(
    id: 1,
    reqNumber: 'REQ-20261028-0001',
    rawStatus: 'APPROVED',
    projectName: 'Hillside Phase 2',
    projectCustomerName: 'Hillside Realty',
    requestedByName: 'Reyes, Mario',
    items: [],
  ),
];

/// A day on which nothing was sold and nothing is stocked: the only state in
/// which a zero is the truth.
const SalesSummary _noSales = SalesSummary(
  from: '2026-10-29',
  to: '2026-10-29',
  totalTransactions: 0,
  totalGross: 0,
  totalVat: 0,
  totalDiscounts: 0,
  days: [],
);

SalesSummary _summary() => const SalesSummary(
  from: '2026-10-29',
  to: '2026-10-29',
  totalTransactions: 34,
  totalGross: 1234865,
  totalVat: 148183.80,
  totalDiscounts: 1250,
  days: [],
);

Product _product({
  required int id,
  required String name,
  required double threshold,
  int variants = 1,
}) => Product(
  id: id,
  categoryId: 1,
  categoryName: 'Cement',
  brandId: 1,
  brandName: 'QB',
  baseName: name,
  description: '',
  imageUrl: '',
  isActive: true,
  variants: [
    ProductVariant(
      id: id,
      productId: id,
      baseUomId: 1,
      minStockThreshold: threshold,
      maxStockLevel: 0,
      variantName: variants > 1 ? '40kg' : 'Standard',
      baseUomCode: 'Bag',
      isActive: true,
    ),
  ],
);

InventoryBatch _batch({
  required int id,
  required int variantId,
  required double qty,
  required double cost,
}) => InventoryBatch(
  id: id,
  variantId: variantId,
  receiptId: 1,
  initialQty: qty,
  currentQty: qty,
  unitCostLanded: cost,
  markupPercentage: 0,
  batchSellingPrice: cost * 1.2,
  expirationDate: null,
  createdAt: DateTime(2026, 10, 20),
);

TransactionRecord _sale({
  required int id,
  required String number,
  required String customer,
  required double amount,
  required DateTime at,
}) => TransactionRecord(
  id: id,
  transactionNo: number,
  transDate: at,
  customerId: 3,
  customerName: customer,
  cashierName: 'Liza Bautista',
  source: 'WALK_IN',
  originalTransactionId: null,
  status: 'COMPLETED',
  grandTotal: amount,
  items: const [],
  payments: const [],
);

class _GoldenProductsRepository extends ProductsRepository {
  _GoldenProductsRepository({
    List<Product> products = const [],
    List<InventoryBatch> batches = const [],
  }) : _snapshot = ProductsSnapshot(products: products, batches: batches),
       super(ProductsService());

  final ProductsSnapshot _snapshot;

  @override
  Future<ProductsSnapshot> loadCatalogue() async => _snapshot;
}

class _GoldenInventoryRepository extends InventoryRepository {
  _GoldenInventoryRepository({this.alerts = const []})
    : super(InventoryService());

  final List<SystemAlert> alerts;

  @override
  Future<List<SystemAlert>> loadAlerts() async => alerts;

  @override
  Future<List<StockAdjustment>> loadAdjustments() async => const [];
}

class _GoldenReportsService extends ReportsService {
  _GoldenReportsService({this.failure, this.summary});

  final String? failure;

  /// Overrides the busy day the loaded goldens show.
  final SalesSummary? summary;

  @override
  Future<SalesSummary> fetchSalesSummary({String? from, String? to}) async {
    final failure = this.failure;
    if (failure != null) throw ReportsServiceException(failure);
    return summary ?? _summary();
  }
}

class _GoldenSalesService extends SalesService {
  _GoldenSalesService({required this.sales});

  final List<TransactionRecord> sales;

  @override
  Future<List<TransactionRecord>> fetchTransactions({String? source}) async =>
      sales;

  @override
  Future<List<QuotationRecord>> fetchQuotations() => throw UnimplementedError();

  @override
  Future<List<SalesOrderRow>> fetchSalesOrders() => throw UnimplementedError();
}

class _GoldenRequisitionRepository extends RequisitionRepository {
  _GoldenRequisitionRepository({required this.requisitions});

  final List<Requisition> requisitions;

  @override
  Future<List<Requisition>> fetchRequisitions() async => requisitions;
}
