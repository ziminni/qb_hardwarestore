@Tags(['golden'])
library;

// C1 visual check: the till with the REAL fonts, written as PNGs so the layout
// can be looked at without a browser (00-shared/VERIFY.md, fallback 3).
//
// Opt in, like `test/shared/widgets/components_golden_test.dart`:
//
//   flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
//     test/features/pos/pos_till_golden_test.dart
//
// 1440 was never looked at before this card (the plan's remaining item 4), so it
// is the first width here. The cart carries a LONG product name and a 7-DIGIT
// total, and the Utang panel is open on a customer who is over their credit
// limit, because those are the three things that run out of room.
//
// States: cart (utang open, long name, 7-digit total) at 1440 / 1100 / 760,
// empty and error at 760.

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/customer.dart';
import 'package:client/data/models/inventory.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/product.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/shift.dart';
import 'package:client/data/models/system_alert.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/customer_repository.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/products_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/customer_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/products_service.dart';
import 'package:client/data/services/shift_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/pos/viewmodels/pos_transaction_viewmodel.dart';
import 'package:client/features/pos/viewmodels/shift_viewmodel.dart';
import 'package:client/features/pos/views/pos_transaction_page.dart';
import 'package:client/features/products/viewmodels/product_tracking_viewmodel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

/// The SDD folder, as an ABSOLUTE path: this test runs in a worktree, where
/// `flutter/../.superpowers` is the worktree's own folder, not the shared one.
/// shortcut: machine specific path per the card brief, upgrade if the repo moves.
const String _goldenDir =
    '/home/yaji/projects/qb_ecosystem/qb_pos_inventory_system'
    '/.superpowers/sdd/ui-refresh/goldens';

const ValueKey _rootKey = ValueKey('c1-till-root');

/// 700 bags at ₱1,764.50: a 7-digit total (₱1,235,150.00). Money must never
/// ellipsize, and the total is the biggest number the cart draws.
const double _unitPrice = 1764.5;
const double _quantity = 700;

void main() {
  const enabled = bool.fromEnvironment('RUN_GOLDENS');

  setUpAll(() async {
    Directory(_goldenDir).createSync(recursive: true);
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
    // The brand fonts stop at Latin, so the peso sign needs the same system
    // fallback the app itself uses.
    for (final candidate in _pesoFontCandidates) {
      if (File(candidate).existsSync()) {
        await _loadFontFile('PesoFallback', candidate);
        break;
      }
    }
  });

  for (final width in const [1440, 1100, 760]) {
    testWidgets('cart with utang open at $width px', (tester) async {
      final till = await _pump(tester, width);
      expect(till.lines.single.quantity, _quantity);
      if (width < 840) await _openCartSheet(tester);
      await _capture('c1-cart-$width.png');
    }, skip: !enabled);
  }

  testWidgets('empty cart at 760 px', (tester) async {
    await _pump(tester, 760, withLine: false);
    await _capture('c1-empty-760.png');
  }, skip: !enabled);

  testWidgets('catalogue error at 760 px', (tester) async {
    await _pump(tester, 760, withLine: false, failCatalogue: true);
    await _capture('c1-error-760.png');
  }, skip: !enabled);
}

Future<void> _capture(String name) async {
  await expectLater(
    find.byKey(_rootKey),
    matchesGoldenFile(Uri.file('$_goldenDir/$name')),
  );
}

/// A narrow window keeps the cart in a sheet behind the black bar (the till's
/// own rule below 840 px), so the picture has to open it to show the panel.
Future<void> _openCartSheet(WidgetTester tester) async {
  await tester.tap(find.text('View cart'));
  await tester.pumpAndSettle();
}

Future<PosTransactionViewmodel> _pump(
  WidgetTester tester,
  int width, {
  bool withLine = true,
  bool failCatalogue = false,
}) async {
  tester.view.physicalSize = Size(width.toDouble(), 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final products = _products();
  final batches = _batches();
  final inventory = InventoryViewmodel.seeded(
    catalogue: failCatalogue
        ? _FailingProductsRepository()
        : FakeProductsRepository(products: products, batches: batches),
    inventory: failCatalogue
        ? _FailingInventoryRepository()
        : FakeInventoryRepository(),
    catalogueLists: FakeCatalogueRepository(),
    products: failCatalogue ? const [] : products,
    batches: failCatalogue ? const [] : batches,
    categories: failCatalogue
        ? const []
        : [
            category(id: 1, name: 'Cement'),
            category(id: 2, name: 'Plywood'),
            category(id: 3, name: 'Steel'),
            category(id: 4, name: 'Plumbing'),
            category(id: 5, name: 'Hardware'),
          ],
  );

  final till = PosTransactionViewmodel(
    inventory,
    customers: _GoldenCustomers(),
  );
  if (withLine) {
    final option = till.saleOptionsFor(till.filteredProducts.first).first;
    expect(till.addLine(option, _quantity), isNull);
    // The account the sale is charged to, with its balance and limit loaded, so
    // the Utang panel is OPEN rather than anonymous.
    till.selectCustomer(_customer);
    await till.loadLedgerForSelection();
  }

  await tester.pumpWidget(
    RepaintBoundary(
      key: _rootKey,
      child: ChangeNotifierProvider<AuthViewmodel>.value(
        value: _cashier(),
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
            ChangeNotifierProvider<ProductTrackingViewmodel>.value(
              value: ProductTrackingViewmodel(),
            ),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            // The real theme, so the shot uses the brand faces and sizes.
            theme: AppTheme.lightTheme.copyWith(
              textTheme: AppTheme.lightTheme.textTheme.apply(
                fontFamilyFallback: const ['PesoFallback'],
              ),
            ),
            home: PosTransactionPage(
              viewmodel: till,
              shiftViewmodel: ShiftViewmodel(service: _OpenShift()),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return till;
}

/// Long on purpose: the cart and the product card must wrap or ellipsize it,
/// never clip it. Five more products behind the first two so the grid is a
/// real shop rather than two cards and half a screen of white, and so the
/// low-stock and out-of-stock badges are in the picture too.
List<Product> _products() => [
  product(
    id: 1,
    name: 'Portland Cement Type 1M 40 kg Holcim Builders Grade Bulk Pallet',
    categoryName: 'Cement',
    brandName: 'Holcim',
    variants: [
      variant(
        id: 1,
        productId: 1,
        name: '40 kg bag, 25 bags per pallet',
        threshold: 50,
        maxStockLevel: 2000,
        baseUomCode: 'BAG',
        sellingUoms: [
          variantUom(id: 1, variantId: 1, price: _unitPrice, uomCode: 'BAG'),
        ],
      ),
    ],
  ),
  product(
    id: 2,
    name: 'Marine Plywood 3/4 in x 4 x 8 ft',
    categoryName: 'Plywood',
    brandName: 'Cocofarm',
    variants: [
      variant(
        id: 2,
        productId: 2,
        name: '3/4 in x 4 x 8 ft',
        threshold: 10,
        maxStockLevel: 200,
        baseUomCode: 'SHEET',
        sellingUoms: [
          variantUom(id: 2, variantId: 2, price: 1480.5, uomCode: 'SHEET'),
        ],
      ),
    ],
  ),
  product(
    id: 3,
    name: 'Deformed Steel Bar 10 mm x 6 m',
    categoryName: 'Steel',
    brandName: 'SteelAsia',
    variants: [
      variant(
        id: 3,
        productId: 3,
        name: '10 mm x 6 m',
        threshold: 40,
        maxStockLevel: 500,
        baseUomCode: 'PC',
        sellingUoms: [
          variantUom(id: 3, variantId: 3, price: 285, uomCode: 'PC'),
        ],
      ),
    ],
  ),
  product(
    id: 4,
    name: 'PVC Pipe Blue Series 1000 2 in x 10 ft',
    categoryName: 'Plumbing',
    brandName: 'Neltex',
    variants: [
      variant(
        id: 4,
        productId: 4,
        name: '2 in x 10 ft',
        threshold: 10,
        maxStockLevel: 200,
        baseUomCode: 'PC',
        sellingUoms: [
          variantUom(id: 4, variantId: 4, price: 415.75, uomCode: 'PC'),
        ],
      ),
    ],
  ),
  product(
    id: 5,
    name: 'Common Wire Nail 4 in',
    categoryName: 'Hardware',
    brandName: 'Crown',
    variants: [
      variant(
        id: 5,
        productId: 5,
        name: '4 in, per kilo',
        threshold: 20,
        maxStockLevel: 400,
        baseUomCode: 'KG',
        sellingUoms: [
          variantUom(id: 5, variantId: 5, price: 88.5, uomCode: 'KG'),
        ],
      ),
    ],
  ),
  product(
    id: 6,
    name: 'Hollow Blocks 4 in',
    categoryName: 'Masonry',
    brandName: 'Lipa',
    variants: [
      variant(
        id: 6,
        productId: 6,
        name: '4 in',
        threshold: 100,
        maxStockLevel: 3000,
        baseUomCode: 'PC',
        sellingUoms: [
          variantUom(id: 6, variantId: 6, price: 22, uomCode: 'PC'),
        ],
      ),
    ],
  ),
  product(
    id: 7,
    name: 'Coco Lumber 2 in x 3 in x 10 ft',
    categoryName: 'Lumber',
    brandName: 'Cocofarm',
    variants: [
      variant(
        id: 7,
        productId: 7,
        name: '2 in x 3 in x 10 ft',
        threshold: 10,
        maxStockLevel: 150,
        baseUomCode: 'PC',
        sellingUoms: [
          variantUom(id: 7, variantId: 7, price: 320, uomCode: 'PC'),
        ],
      ),
    ],
  ),
];

List<InventoryBatch> _batches() => [
  batch(id: 1, variantId: 1, qty: 900, cost: 1400),
  batch(id: 2, variantId: 2, qty: 120, cost: 1100),
  // Low stock: the warning badge is in the picture too.
  batch(id: 3, variantId: 3, qty: 6, cost: 240),
  // Not zero: the till drops a variant with no stock on hand, so an
  // out-of-stock card can never reach the grid.
  batch(id: 4, variantId: 4, qty: 18, cost: 360),
  batch(id: 5, variantId: 5, qty: 240, cost: 70),
  batch(id: 6, variantId: 6, qty: 1500, cost: 18),
  batch(id: 7, variantId: 7, qty: 64, cost: 260),
];

/// Over their limit ON PURPOSE: that is the widest line the panel draws, and
/// the one a cashier reads at a glance.
const Customer _customer = Customer(
  id: 12,
  name: 'Dela Cruz Construction and General Merchandise',
  customerType: 'CONSTRUCTION_FIRM',
  totalCreditLimit: 200000,
);

AuthViewmodel _cashier() =>
    AuthViewmodel(AuthRepository(AuthService()))
      ..user = const User(
        id: 7,
        username: 'cashier',
        email: 'cashier@buildpro.ph',
        fullName: 'Ana Cruz',
        role: Role(id: 3, name: 'pos', displayName: 'Cashier'),
        isActive: true,
      );

class _GoldenCustomers extends CustomerRepository {
  _GoldenCustomers() : super(CustomerService());

  @override
  Future<CustomerLedgerSummary> fetchLedgerSummary(int customerId) async =>
      CustomerLedgerSummary(
        customerId: customerId,
        customerName: _customer.name,
        totalBalance: 150000,
        openCount: 3,
        overdueCount: 1,
      );
}

class _OpenShift extends ShiftService {
  @override
  Future<Shift?> fetchCurrent() async => Shift(
    id: 4,
    cashierName: 'Ana Cruz',
    status: Shift.openStatus,
    openingFloat: 5000,
    closingCount: null,
    openedAt: DateTime(2026, 10, 29, 8),
    closedAt: null,
    notes: '',
    zReading: null,
  );

  @override
  Future<List<Shift>> fetchAll() async => const [];
}

class _FailingProductsRepository extends ProductsRepository {
  _FailingProductsRepository() : super(ProductsService());

  @override
  Future<ProductsSnapshot> loadCatalogue() async =>
      throw const ProductsServiceException(
        'Cannot connect to the BuildPro server.',
      );
}

class _FailingInventoryRepository extends InventoryRepository {
  _FailingInventoryRepository() : super(InventoryService());

  @override
  Future<List<SystemAlert>> loadAlerts() async =>
      throw const InventoryServiceException('Cannot connect.');

  @override
  Future<List<StockAdjustment>> loadAdjustments() async => const [];
}

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
