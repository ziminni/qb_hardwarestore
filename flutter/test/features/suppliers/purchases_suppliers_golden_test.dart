@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/supplier_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/supplier_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/features/suppliers/views/purchases_page.dart';
import 'package:client/features/suppliers/views/suppliers_page.dart';
import 'package:client/features/suppliers/widgets/purchases_form_dialog.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

/// The fallback visual check for K7 (00-shared/VERIFY.md, fallback 3): the real
/// Purchases and Suppliers pages inside their real Stock Manager shell, and the
/// New purchase order dialog on its own, painted with the real fonts and written
/// as PNGs into the SDD folder.
///
/// Opt in, so a font or platform difference never fails the normal suite:
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/suppliers/purchases_suppliers_golden_test.dart
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
    testWidgets('purchases list at ${entry.$1} px', (tester) async {
      await _pumpPage(tester, entry.$2, const PurchasesPage(), _loaded());

      expect(find.byType(ErrorBanner), findsNothing);
      expect(find.text('PO-41'), findsOneWidget);

      await expectLater(
        find.byKey(pageKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/k7-purchases-list-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }

  testWidgets('suppliers list at 1100 px', (tester) async {
    await _pumpPage(
      tester,
      const Size(1100, 900),
      const SuppliersPage(),
      _loaded(),
    );

    expect(find.byType(ErrorBanner), findsNothing);
    expect(find.text('Bohol Cement Traders'), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(
        Uri.file('${goldenDir.path}/k7-suppliers-list-1100.png'),
      ),
    );
  }, skip: !enabled);

  testWidgets('purchases empty at 760 px', (tester) async {
    await _pumpPage(
      tester,
      const Size(760, 900),
      const PurchasesPage(),
      _empty(),
    );

    expect(find.text('No purchase orders yet.'), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(
        Uri.file('${goldenDir.path}/k7-purchases-empty-760.png'),
      ),
    );
  }, skip: !enabled);

  testWidgets('purchases error at 760 px', (tester) async {
    final store = _loaded()
      ..failure = 'The purchase orders could not be loaded.';
    await _pumpPage(tester, const Size(760, 900), const PurchasesPage(), store);

    expect(find.byType(ErrorBanner), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(
        Uri.file('${goldenDir.path}/k7-purchases-error-760.png'),
      ),
    );
  }, skip: !enabled);

  for (final entry in const [
    ('1366x768', Size(1366, 768)),
    ('760x900', Size(760, 900)),
  ]) {
    testWidgets('purchase order dialog at ${entry.$1}', (tester) async {
      await _pumpDialog(tester, entry.$2);

      expect(find.text('Place order'), findsOneWidget);

      await expectLater(
        find.byKey(pageKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/k7-po-dialog-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }
}

const pageKey = ValueKey('PurchasesSuppliersGolden');

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

ThemeData get _theme => AppTheme.lightTheme.copyWith(
  textTheme: AppTheme.lightTheme.textTheme.apply(
    fontFamilyFallback: const [_pesoFallbackFamily],
  ),
);

Future<void> _pumpPage(
  WidgetTester tester,
  Size size,
  Widget page,
  _GoldenRepository repository,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});

  final viewmodel = SuppliersPurchasesViewmodel(repository: repository);
  await viewmodel.load();

  await tester.pumpWidget(
    RepaintBoundary(
      key: pageKey,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>(
            create: (_) => AuthViewmodel(AuthRepository(AuthService())),
          ),
          ChangeNotifierProvider<SuppliersPurchasesViewmodel>.value(
            value: viewmodel,
          ),
          ChangeNotifierProvider<InventoryViewmodel>(
            create: (_) => InventoryViewmodel(
              products: FakeProductsRepository(),
              inventory: FakeInventoryRepository(),
              catalogue: FakeCatalogueRepository(),
            ),
          ),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: _theme,
          home: page,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpDialog(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});

  final inventory = InventoryViewmodel(
    products: FakeProductsRepository(
      products: [
        product(
          id: 6,
          name: 'Portland Cement',
          categoryName: 'Cement',
          variants: [
            variant(id: 8, productId: 6, name: '40 kg bag', baseUomCode: 'BAG'),
          ],
        ),
        product(
          id: 7,
          name: 'Deformed Steel Bar 10 mm x 6 m Grade 60',
          categoryName: 'Steel bars',
          variants: [
            variant(
              id: 9,
              productId: 7,
              name: '10 mm x 6 m',
              baseUomCode: 'PC',
            ),
          ],
        ),
      ],
    ),
    inventory: FakeInventoryRepository(),
    catalogue: FakeCatalogueRepository(),
  );
  await inventory.load();

  await tester.pumpWidget(
    RepaintBoundary(
      key: pageKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _theme,
        home: Scaffold(
          backgroundColor: const Color(0xFFF8F6F0),
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () => showDialog<PurchaseOrderFormResult>(
                  context: context,
                  builder: (_) => PurchasesFormDialog(
                    suppliers: _loaded().suppliers,
                    products: inventory.products,
                    costFor: (_) => 240,
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// A whole PO book: a long supplier name, every status, and a seven digit total.
_GoldenRepository _loaded() => _GoldenRepository(
  suppliers: const [
    Supplier(
      id: 7,
      companyName: 'Bohol Cement Traders',
      contactPerson: 'Rina Lim',
      phone: '0917 000 1111',
      email: 'orders@boholcement.ph',
      address: 'Tagbilaran City',
    ),
    Supplier(
      id: 9,
      companyName: 'Cebu Steel Works and General Merchandise Incorporated',
      contactPerson: 'Dan Uy',
      phone: '0918 000 2222',
      email: 'sales@cebusteel.ph',
      address: 'Mandaue City',
    ),
    Supplier(
      id: 11,
      companyName: 'Neltex Distribution Cebu',
      contactPerson: 'Jo Tan',
      phone: '0919 000 3333',
      email: 'neltex@cebu.ph',
      address: 'Cebu City',
      isActive: false,
    ),
  ],
  purchases: [
    PurchaseOrder(
      id: 41,
      supplierId: 9,
      supplierName: '',
      orderDate: DateTime(2026, 10, 20),
      expectedDelivery: DateTime(2026, 10, 25),
      status: PurchaseStatus.ordered,
      createdBy: 'Ana Lopez',
      notes: 'Replenishment',
      items: const [
        PurchaseItem(
          productName: '',
          variantName: '10 mm x 6 m',
          sku: '',
          quantity: 20000,
          receivedQuantity: 0,
          unitCost: 240,
        ),
      ],
    ),
    PurchaseOrder(
      id: 40,
      supplierId: 7,
      supplierName: '',
      orderDate: DateTime(2026, 10, 18),
      expectedDelivery: null,
      status: PurchaseStatus.draft,
      createdBy: 'Ana Lopez',
      notes: '',
      items: const [
        PurchaseItem(
          productName: '',
          variantName: '40 kg bag',
          sku: '',
          quantity: 50,
          receivedQuantity: 0,
          unitCost: 285,
        ),
      ],
    ),
    PurchaseOrder(
      id: 39,
      supplierId: 7,
      supplierName: '',
      orderDate: DateTime(2026, 10, 12),
      expectedDelivery: DateTime(2026, 10, 16),
      status: PurchaseStatus.partial,
      createdBy: 'Ana Lopez',
      notes: 'Second delivery expected',
      items: const [
        PurchaseItem(
          productName: '',
          variantName: '40 kg bag',
          sku: '',
          quantity: 120,
          receivedQuantity: 60,
          unitCost: 285,
        ),
      ],
    ),
    PurchaseOrder(
      id: 38,
      supplierId: 11,
      supplierName: '',
      orderDate: DateTime(2026, 10, 2),
      expectedDelivery: DateTime(2026, 10, 8),
      status: PurchaseStatus.complete,
      createdBy: 'Ana Lopez',
      notes: '',
      items: const [
        PurchaseItem(
          productName: '',
          variantName: 'PVC Pipe 2 in x 3 m',
          sku: '',
          quantity: 40,
          receivedQuantity: 40,
          unitCost: 320,
        ),
      ],
    ),
    PurchaseOrder(
      id: 37,
      supplierId: 11,
      supplierName: '',
      orderDate: DateTime(2026, 9, 28),
      expectedDelivery: null,
      status: PurchaseStatus.cancelled,
      createdBy: 'Ana Lopez',
      notes: '',
      items: const [
        PurchaseItem(
          productName: '',
          variantName: 'PVC Pipe 2 in x 3 m',
          sku: '',
          quantity: 10,
          receivedQuantity: 0,
          unitCost: 320,
        ),
      ],
    ),
  ],
);

_GoldenRepository _empty() => _GoldenRepository();

/// Answers both reads from the fixtures above, or fails them on request.
class _GoldenRepository extends SupplierRepository {
  _GoldenRepository({this.suppliers = const [], this.purchases = const []});

  List<Supplier> suppliers;
  List<PurchaseOrder> purchases;
  String? failure;

  @override
  Future<List<Supplier>> fetchSuppliers() async {
    final failure = this.failure;
    if (failure != null) throw SupplierServiceException(failure);
    return suppliers;
  }

  @override
  Future<List<PurchaseOrder>> fetchPurchaseOrders() async {
    final failure = this.failure;
    if (failure != null) throw SupplierServiceException(failure);
    return purchases;
  }
}
