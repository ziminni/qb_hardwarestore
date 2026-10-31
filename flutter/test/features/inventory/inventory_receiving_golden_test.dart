@Tags(['golden'])
library;

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/models/role.dart';
import 'package:client/data/models/supplier.dart';
import 'package:client/data/models/user.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/repositories/supplier_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/receiving_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_receiving_page.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/phase4_fakes.dart';

/// The fallback visual check for K8 (00-shared/VERIFY.md, fallback 3): the real
/// Receiving page inside its real Stock Manager shell, painted with the real
/// fonts and written as PNGs into the SDD folder.
///
/// Opt in, so a font or platform difference never fails the normal suite:
///
/// ```
/// flutter test --tags golden --dart-define=RUN_GOLDENS=true --update-goldens \
///   test/features/inventory/inventory_receiving_golden_test.dart
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
    // The test harness does not load the Material icon font, so every Icon would
    // be a box in the PNG.
    final icons = _flutterSdkFile(
      'bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons != null) {
      await _loadFontFile('MaterialIcons', icons);
    }
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
    testWidgets('receiving workspace at ${entry.$1} px', (tester) async {
      await _pumpReceiving(tester, entry.$2);

      expect(find.byType(ErrorBanner), findsNothing);
      expect(find.text('1 Pick a purchase order'), findsOneWidget);
      // Open on the first order so the receipt steps carry their real content
      // (ordered, already received, the quantity boxes) in the shot.
      await tester.tap(find.byKey(const Key('receiving-order-2')));
      await tester.pumpAndSettle();
      expect(find.text('2 Record receipt'), findsOneWidget);

      await expectLater(
        find.byKey(pageKey),
        matchesGoldenFile(
          Uri.file('${goldenDir.path}/k8-list-${entry.$1}.png'),
        ),
      );
    }, skip: !enabled);
  }

  testWidgets('received deliveries at 1100 px', (tester) async {
    await _pumpReceiving(
      tester,
      const Size(1100, 900),
      receipts: _receivedDeliveries,
    );

    await tester.tap(find.text('Received deliveries'));
    await tester.pumpAndSettle();
    expect(find.text('DR-9001'), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/k8-history-1100.png')),
    );
  }, skip: !enabled);

  testWidgets('receiving empty at 760 px', (tester) async {
    await _pumpReceiving(tester, const Size(760, 900), orders: const []);

    expect(
      find.textContaining('No order is waiting to be received'),
      findsOneWidget,
    );

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/k8-empty-760.png')),
    );
  }, skip: !enabled);

  testWidgets('receiving error at 760 px', (tester) async {
    await _pumpReceiving(
      tester,
      const Size(760, 900),
      failure: 'The purchase orders could not be read.',
    );

    expect(find.byType(ErrorBanner), findsOneWidget);

    await expectLater(
      find.byKey(pageKey),
      matchesGoldenFile(Uri.file('${goldenDir.path}/k8-error-760.png')),
    );
  }, skip: !enabled);
}

const pageKey = ValueKey('InventoryReceivingGolden');

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

Future<void> _pumpReceiving(
  WidgetTester tester,
  Size size, {
  List<PurchaseOrderRecord>? orders,
  List<GoodsReceiptRecord> receipts = const [],
  String? failure,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});

  final suppliers = SuppliersPurchasesViewmodel(
    repository: _StubSupplierRepository(),
  );
  await suppliers.load();

  await tester.pumpWidget(
    RepaintBoundary(
      key: pageKey,
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthViewmodel>.value(
            value: _stockManagerAuth(),
          ),
          ChangeNotifierProvider<SuppliersPurchasesViewmodel>.value(
            value: suppliers,
          ),
          // The label dialog reads the catalogue; the shot never opens it, but
          // the page must be pumped inside the same providers the real route has.
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
          theme: AppTheme.lightTheme.copyWith(
            // Only the goldens: lets a peso sign fall back to the system font
            // the app itself uses, because the brand fonts stop at Latin.
            textTheme: AppTheme.lightTheme.textTheme.apply(
              fontFamilyFallback: const [_pesoFallbackFamily],
            ),
          ),
          home: InventoryReceivingPage(
            viewmodel: ReceivingViewmodel(
              service: _StubInventoryService(
                orders: orders ?? _waitingOrders,
                receipts: receipts,
                failure: failure,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

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

/// Two suppliers, so a row can print a real company name instead of an id.
class _StubSupplierRepository extends SupplierRepository {
  @override
  Future<List<Supplier>> fetchSuppliers() async => const [
    Supplier(
      id: 2,
      companyName: 'Mandaue Hardware Trading',
      contactPerson: 'Rico Bautista',
      phone: '032 123 4567',
      email: 'orders@mandauehardware.ph',
      address: 'Mandaue City',
    ),
    Supplier(
      id: 3,
      companyName: 'Cebu Steel and Construction Supply Incorporated',
      contactPerson: 'Liza Tan',
      phone: '032 765 4321',
      email: 'sales@cebusteel.ph',
      address: 'Cebu City',
    ),
  ];

  @override
  Future<List<PurchaseOrder>> fetchPurchaseOrders() async => const [];
}

class _StubInventoryService extends InventoryService {
  _StubInventoryService({
    required this.orders,
    this.receipts = const [],
    this.failure,
  });

  final List<PurchaseOrderRecord> orders;
  final List<GoodsReceiptRecord> receipts;
  final String? failure;

  @override
  Future<List<PurchaseOrderRecord>> fetchPurchaseOrders() async {
    if (failure case final message?) {
      throw InventoryServiceException(message);
    }
    return orders;
  }

  // A failed order read is the page's own error state; the history is a second
  // read and stays empty in that shot.
  @override
  Future<List<GoodsReceiptRecord>> fetchGoodsReceipts() async => receipts;

  @override
  Future<GoodsReceiptRecord> createReceipt({
    required int poId,
    required List<ReceiptLine> items,
    String deliveryReceiptNo = '',
  }) async => GoodsReceiptRecord(
    id: 5,
    poId: poId,
    deliveryReceiptNo: deliveryReceiptNo,
    batches: const [],
  );

  @override
  Future<List<InventoryBatch>> processReceipt(int receiptId) async => const [
    InventoryBatch(
      id: 21,
      variantId: 8,
      receiptId: 5,
      initialQty: 120,
      currentQty: 120,
      unitCostLanded: 285,
      markupPercentage: 0,
      batchSellingPrice: 285,
      expirationDate: null,
      createdAt: null,
    ),
  ];
}

/// Three deliveries: two processed, one recorded but not yet in stock, with a
/// long receiver name and a short DR number that must not be cut.
final List<GoodsReceiptRecord> _receivedDeliveries = [
  GoodsReceiptRecord(
    id: 12,
    poId: 3,
    deliveryReceiptNo: 'DR-9001',
    batches: [],
    receivedByName: 'Ana Lopez',
    receiveDate: DateTime(2026, 10, 27, 8, 15),
    lines: [
      GoodsReceiptLine(
        id: 1,
        poItemId: 31,
        variantName: 'Deformed Steel Bar 10 mm x 6 m Grade 60',
        qty: 8,
      ),
    ],
    processedAt: null,
  ),
  GoodsReceiptRecord(
    id: 11,
    poId: 2,
    deliveryReceiptNo: 'DR-8842-A',
    batches: [],
    receivedByName: 'Maria Concepcion Villanueva Reyes',
    receiveDate: DateTime(2026, 10, 25, 9, 30),
    processedAt: DateTime(2026, 10, 25, 9, 45),
    lines: [
      GoodsReceiptLine(
        id: 2,
        poItemId: 21,
        variantName: 'Portland Cement 40 kg',
        qty: 120,
      ),
      GoodsReceiptLine(
        id: 3,
        poItemId: 22,
        variantName: 'Marine Plywood 3/4 in x 4 x 8 ft',
        qty: 40,
      ),
    ],
  ),
  GoodsReceiptRecord(
    id: 10,
    poId: 4,
    deliveryReceiptNo: '',
    batches: [],
    receivedByName: 'Ana Lopez',
    receiveDate: DateTime(2026, 10, 21, 16, 5),
    lines: [],
    processedAt: null,
  ),
];

/// Four orders in the two states the screen can receive: three ORDERED, one
/// PARTIAL with two of ten already delivered, one long product name and one
/// supplier name long enough to test the ellipsis.
const List<PurchaseOrderRecord> _waitingOrders = [
  PurchaseOrderRecord(
    id: 2,
    supplierId: 2,
    status: 'ORDERED',
    notes: '',
    items: [
      PurchaseOrderItem(
        id: 21,
        poId: 2,
        variantId: 8,
        variantName: 'Portland Cement 40 kg',
        orderedQty: 120,
        unitCost: 285,
        receivedQty: 0,
      ),
      PurchaseOrderItem(
        id: 22,
        poId: 2,
        variantId: 9,
        variantName: 'Marine Plywood 3/4 in x 4 x 8 ft',
        orderedQty: 40,
        unitCost: 1480.5,
        receivedQty: 0,
      ),
    ],
  ),
  PurchaseOrderRecord(
    id: 3,
    supplierId: 3,
    status: 'PARTIAL',
    notes: '',
    items: [
      PurchaseOrderItem(
        id: 31,
        poId: 3,
        variantId: 11,
        variantName: 'Deformed Steel Bar 10 mm x 6 m Grade 60',
        orderedQty: 10,
        unitCost: 9000,
        receivedQty: 2,
      ),
    ],
  ),
  PurchaseOrderRecord(
    id: 4,
    supplierId: 3,
    status: 'ORDERED',
    notes: '',
    items: [
      PurchaseOrderItem(
        id: 41,
        poId: 4,
        variantId: 12,
        variantName: 'PVC Pipe 2 in x 3 m',
        orderedQty: 60,
        unitCost: 320,
        receivedQty: 0,
      ),
    ],
  ),
  PurchaseOrderRecord(
    id: 5,
    supplierId: 2,
    status: 'ORDERED',
    notes: '',
    items: [
      PurchaseOrderItem(
        id: 51,
        poId: 5,
        variantId: 13,
        variantName: 'Latex Paint White 4 L',
        orderedQty: 24,
        unitCost: 640,
        receivedQty: 0,
      ),
      PurchaseOrderItem(
        id: 52,
        poId: 5,
        variantId: 14,
        variantName: 'Paint brush 4 in',
        orderedQty: 36,
        unitCost: 95,
        receivedQty: 0,
      ),
      PurchaseOrderItem(
        id: 53,
        poId: 5,
        variantId: 15,
        variantName: 'Sand paper 100 grit',
        orderedQty: 100,
        unitCost: 12,
        receivedQty: 0,
      ),
    ],
  ),
];
