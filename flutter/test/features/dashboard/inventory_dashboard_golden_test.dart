@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/repositories/supplier_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/dashboard/views/inventory_dashboard.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

/// The fallback visual check for K1 (00-shared/VERIFY.md, fallback 3): the real
/// Stock Manager dashboard, inside its real shell, painted with the real fonts
/// and written as PNGs into the SDD folder so the layout can be looked at
/// without a browser.
///
/// Opt in, so a font or platform difference never fails the normal suite:
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/dashboard/inventory_dashboard_golden_test.dart
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
    testWidgets('k1 dashboard at ${entry.$1} px', (tester) async {
      await _pumpDashboard(tester, entry.$2, await _loadedStore());

      expect(find.byType(ErrorBanner), findsNothing);
      // The panels this card exists for are all on screen.
      expect(find.text('Restock queue'), findsOneWidget);
      expect(find.text('Waiting to receive'), findsOneWidget);
      expect(find.text('Recent adjustments'), findsOneWidget);
      // Seven digits in the value tile, so the money is tested for grouping.
      expect(find.text('₱1,234,865.00'), findsOneWidget);

      await expectLater(
        find.byKey(pageKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/k1-loaded-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }

  testWidgets('k1 dashboard empty at 760 px', (tester) async {
    await _pumpDashboard(tester, const Size(760, 900), await _emptyStore());

    expect(find.text('No products available.'), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/k1-empty-760.png')),
    );
  }, skip: !enabled);

  testWidgets('k1 dashboard error at 760 px', (tester) async {
    await _pumpDashboard(tester, const Size(760, 900), await _failedStore());

    expect(find.byType(ErrorBanner), findsOneWidget);
    expect(find.text('Cannot connect to the BuildPro server.'), findsOneWidget);
    // One failure, not a failure plus an empty list.
    expect(find.text('No products available.'), findsNothing);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/k1-error-760.png')),
    );
  }, skip: !enabled);
}

const pageKey = ValueKey('InventoryDashboardGolden');

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

Future<void> _pumpDashboard(
  WidgetTester tester,
  Size size,
  ({InventoryViewmodel inventory, SuppliersPurchasesViewmodel purchases})
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
            value: _stockManagerAuth(),
          ),
          ChangeNotifierProvider<InventoryViewmodel>.value(
            value: stores.inventory,
          ),
          ChangeNotifierProvider<SuppliersPurchasesViewmodel>.value(
            value: stores.purchases,
          ),
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
          home: const InventoryDashboard(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The Stock Manager the page reads its role from.
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

/// A catalogue a real branch would have: one out of stock, four low, two
/// healthy, one long name and a value in the millions.
Future<({InventoryViewmodel inventory, SuppliersPurchasesViewmodel purchases})>
_loadedStore() async {
  SharedPreferences.setMockInitialValues({});
  final products = [
    product(
      id: 1,
      name: 'Deformed Steel Bar 10 mm x 6 m Grade 60',
      categoryName: 'Steel bars',
      variants: [
        variant(id: 1, productId: 1, name: '10 mm x 6 m', threshold: 80),
      ],
    ),
    product(
      id: 2,
      name: 'Portland Cement',
      categoryName: 'Cement',
      variants: [variant(id: 2, productId: 2, name: '40kg', threshold: 50)],
    ),
    product(
      id: 3,
      name: 'Tiles 60x60',
      categoryName: 'Tiles',
      variants: [variant(id: 3, productId: 3, name: 'Glossy', threshold: 40)],
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
      name: 'PVC Pipe',
      categoryName: 'Plumbing',
      variants: [
        variant(id: 5, productId: 5, name: '1/2 inch', threshold: 100),
      ],
    ),
    product(
      id: 6,
      name: 'Latex Paint White 4 L',
      categoryName: 'Paint',
      variants: [variant(id: 6, productId: 6, name: 'Glossy', threshold: 10)],
    ),
    product(
      id: 7,
      name: 'Common Nails 2 inch',
      categoryName: 'Hardware',
      variants: [variant(id: 7, productId: 7, name: 'Kilo', threshold: 60)],
    ),
  ];
  final inventory = InventoryViewmodel(
    products: FakeProductsRepository(
      products: products,
      batches: [
        // Out of stock: nothing left of the steel bars.
        batch(id: 2, variantId: 2, qty: 12, cost: 240),
        batch(id: 3, variantId: 3, qty: 25, cost: 320),
        // Seven digits into the value tile.
        batch(id: 4, variantId: 4, qty: 1199000, cost: 1),
        batch(id: 5, variantId: 5, qty: 41, cost: 95),
        batch(id: 6, variantId: 6, qty: 40, cost: 480),
        batch(id: 7, variantId: 7, qty: 9, cost: 210),
      ],
    ),
    inventory: FakeInventoryRepository(
      adjustments: [
        StockAdjustment(
          id: 12,
          variantId: 4,
          userId: 2,
          adjustmentType: StockAdjustmentType.correction,
          quantityAdjusted: 40,
          remarks: 'Recount after the delivery was split',
          timestamp: DateTime(2026, 10, 29, 15, 40),
        ),
        StockAdjustment(
          id: 11,
          variantId: 2,
          userId: 2,
          adjustmentType: StockAdjustmentType.damage,
          quantityAdjusted: -2,
          remarks: 'torn bag',
          timestamp: DateTime(2026, 10, 29, 11, 5),
        ),
        StockAdjustment(
          id: 10,
          variantId: 3,
          userId: 4,
          adjustmentType: StockAdjustmentType.shrinkage,
          quantityAdjusted: -3,
          remarks: 'broken during handling',
          timestamp: DateTime(2026, 10, 28, 16, 20),
        ),
        StockAdjustment(
          id: 9,
          variantId: 5,
          userId: 4,
          adjustmentType: StockAdjustmentType.returnToSupplier,
          quantityAdjusted: -10,
          remarks: '',
          timestamp: DateTime(2026, 10, 28, 9, 10),
        ),
      ],
    ),
    catalogue: FakeCatalogueRepository(),
  );
  await inventory.load();

  final purchases = SuppliersPurchasesViewmodel(
    repository: _GoldenSupplierRepository(),
  );
  await purchases.load();
  return (inventory: inventory, purchases: purchases);
}

Future<({InventoryViewmodel inventory, SuppliersPurchasesViewmodel purchases})>
_emptyStore() async {
  SharedPreferences.setMockInitialValues({});
  final inventory = InventoryViewmodel(
    products: FakeProductsRepository(),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );
  await inventory.load();
  final purchases = SuppliersPurchasesViewmodel(
    repository: _GoldenSupplierRepository(orders: const []),
  );
  await purchases.load();
  return (inventory: inventory, purchases: purchases);
}

Future<({InventoryViewmodel inventory, SuppliersPurchasesViewmodel purchases})>
_failedStore() async {
  SharedPreferences.setMockInitialValues({});
  final inventory = InventoryViewmodel(
    products: _FailingProductsRepository(),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );
  await inventory.load();
  final purchases = SuppliersPurchasesViewmodel(
    repository: _GoldenSupplierRepository(orders: const []),
  );
  await purchases.load();
  return (inventory: inventory, purchases: purchases);
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

/// The suppliers and purchase orders the Receiving screen would show.
class _GoldenSupplierRepository extends SupplierRepository {
  _GoldenSupplierRepository({List<PurchaseOrder>? orders})
    : purchases = orders ?? _defaultOrders;

  final List<PurchaseOrder> purchases;

  @override
  Future<List<Supplier>> fetchSuppliers() async => const [
    Supplier(
      id: 1,
      companyName: 'Cebu Hardware Trading',
      contactPerson: 'Rosa Lim',
      phone: '032 233 1180',
      email: 'sales@cebuhardware.ph',
      address: 'Mandaue City',
    ),
    Supplier(
      id: 2,
      companyName: 'Mindanao Steel Works',
      contactPerson: 'Ben Cruz',
      phone: '082 221 4477',
      email: 'orders@mindanaosteel.ph',
      address: 'Davao City',
    ),
  ];

  @override
  Future<List<PurchaseOrder>> fetchPurchaseOrders() async => purchases;
}

PurchaseOrder _order({
  required int id,
  required int supplierId,
  required PurchaseStatus status,
  required double ordered,
  required double received,
  DateTime? expectedDelivery,
}) => PurchaseOrder(
  id: id,
  supplierId: supplierId,
  supplierName: '',
  orderDate: DateTime(2026, 10, 22),
  expectedDelivery: expectedDelivery,
  status: status,
  createdBy: 'Ana Lopez',
  notes: '',
  items: [
    PurchaseItem(
      productName: '',
      variantName: 'Portland Cement 40kg',
      sku: '',
      quantity: ordered,
      receivedQuantity: received,
      unitCost: 240,
    ),
  ],
);

final List<PurchaseOrder> _defaultOrders = [
  _order(
    id: 41,
    supplierId: 1,
    status: PurchaseStatus.partial,
    ordered: 1200,
    received: 400,
    expectedDelivery: DateTime(2026, 10, 24),
  ),
  _order(
    id: 42,
    supplierId: 2,
    status: PurchaseStatus.ordered,
    ordered: 300,
    received: 0,
    expectedDelivery: DateTime(2026, 10, 30),
  ),
  _order(
    id: 43,
    supplierId: 1,
    status: PurchaseStatus.ordered,
    ordered: 60,
    received: 0,
  ),
  // Not waiting for anything: one delivery came in, one was never placed.
  _order(
    id: 44,
    supplierId: 2,
    status: PurchaseStatus.complete,
    ordered: 50,
    received: 50,
  ),
  _order(
    id: 45,
    supplierId: 1,
    status: PurchaseStatus.draft,
    ordered: 80,
    received: 0,
  ),
];
