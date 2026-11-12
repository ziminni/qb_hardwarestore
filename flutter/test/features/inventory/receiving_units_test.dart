// Phase 5 F1 (decision 18): receiving counts in the PO line's unit.
//
// The line's `qty` is counted in the unit the order named, and the SERVER owns
// the conversion to base stock. So the client must:
//   * name that unit on the count box, the line caption and the helper,
//   * show the base equivalent (2 BAG = 50 KG) without letting it leak into the
//     payload — a receipt that sent 50 would stock fifty bags' worth of kilos,
//   * keep the old meaning when the server sends no unit at all (factor 1).

import 'dart:io';

import 'package:client/core/theme/app_theme.dart';
import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/inventory_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/receiving_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_receiving_page.dart';
import 'package:client/shared/widgets/error_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../../support/phase4_fakes.dart';

Future<void> _loadAppFonts() async {
  for (final (family, files) in [
    ('OpenSans', ['OpenSans-Regular.ttf', 'OpenSans-Bold.ttf']),
    ('Cinzel', ['Cinzel-Regular.ttf', 'Cinzel-Bold.ttf']),
  ]) {
    final loader = FontLoader(family);
    for (final file in files) {
      final bytes = await File('assets/fonts/$file').readAsBytes();
      loader.addFont(Future.value(bytes.buffer.asByteData()));
    }
    await loader.load();
  }
}

class _StubInventoryService extends InventoryService {
  _StubInventoryService() : super();

  List<PurchaseOrderRecord> orders = const [];
  List<ReceiptLine> sentLines = const [];

  /// The server's own refusal sentence, when this stub plays a refused receipt.
  String? refusal;

  @override
  Future<List<PurchaseOrderRecord>> fetchPurchaseOrders() async => orders;

  @override
  Future<List<GoodsReceiptRecord>> fetchGoodsReceipts() async => const [];

  @override
  Future<GoodsReceiptRecord> createReceipt({
    required int poId,
    required List<ReceiptLine> items,
    String deliveryReceiptNo = '',
  }) async {
    sentLines = items;
    final refusal = this.refusal;
    if (refusal != null) throw InventoryServiceException(refusal);
    return GoodsReceiptRecord(
      id: 5,
      poId: poId,
      deliveryReceiptNo: deliveryReceiptNo,
      batches: const [],
    );
  }

  @override
  Future<List<InventoryBatch>> processReceipt(int receiptId) async => const [];
}

/// One PO line exactly as Phase 5 B1 serialises it: the selling unit and its
/// read-only copies ride along with the line.
Map<String, dynamic> _unitLine() => {
  'id': 11,
  'po': 1,
  'variant': 8,
  'variant_name': 'Portland 40kg',
  'variant_uom': 11,
  'uom_code': 'BAG',
  'conversion_factor': '25.00',
  'uom_is_whole': true,
  'ordered_qty': '10.00',
  'unit_cost': '250.00',
  'received_qty': '0.00',
};

/// The same line from a server that predates units: no `variant_uom`, no copies.
/// It still means base units, so nothing may be guessed from it.
Map<String, dynamic> _oldWireLine() => {
  'id': 11,
  'po': 1,
  'variant': 8,
  'variant_name': 'Portland 40kg',
  'ordered_qty': '10.00',
  'unit_cost': '250.00',
  'received_qty': '0.00',
};

PurchaseOrderRecord _order(Map<String, dynamic> line) => PurchaseOrderRecord(
  id: 1,
  supplierId: 2,
  status: 'ORDERED',
  notes: '',
  items: [PurchaseOrderItem.fromJson(line)],
);

/// The catalogue the receiving screen reads a base unit name from: this variant
/// is stocked in KG, and its bag is the factor-25 selling unit.
InventoryViewmodel _inventory() => InventoryViewmodel(
  products: FakeProductsRepository(
    products: [
      product(
        id: 6,
        name: 'Portland Cement',
        variants: [
          variant(
            id: 8,
            productId: 6,
            name: 'Portland 40kg',
            baseUomId: 2,
            baseUomCode: 'KG',
            sellingUoms: [
              variantUom(
                id: 11,
                variantId: 8,
                uomId: 1,
                uomCode: 'BAG',
                uomName: 'Bag',
                factor: 25,
                isWhole: true,
                price: 250,
              ),
              variantUom(id: 12, variantId: 8, uomId: 2, uomCode: 'KG'),
            ],
          ),
        ],
      ),
    ],
  ),
  inventory: FakeInventoryRepository(),
  catalogue: FakeCatalogueRepository(),
);

Future<_StubInventoryService> _pump(
  WidgetTester tester, {
  required Map<String, dynamic> line,
  Size size = const Size(1600, 1400),
  String? refusal,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final service = _StubInventoryService()
    ..orders = [_order(line)]
    ..refusal = refusal;
  final inventory = _inventory();
  await inventory.load();
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        // The shell reads the signed-in user, exactly as the real route does.
        ChangeNotifierProvider<AuthViewmodel>.value(
          value: AuthViewmodel(AuthRepository(AuthService())),
        ),
        ChangeNotifierProvider<InventoryViewmodel>.value(value: inventory),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: InventoryReceivingPage(
          viewmodel: ReceivingViewmodel(service: service),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  setUpAll(_loadAppFonts);
  tearDown(() => ReceivingViewmodel.pendingPurchaseOrderId = null);

  testWidgets('a 2 BAG count shows its 50 KG equivalent and sends 2', (
    tester,
  ) async {
    final service = await _pump(tester, line: _unitLine());

    await tester.tap(find.byKey(const Key('receiving-order-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Ordered 10 BAG'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('receiving-qty-11')), '2');
    await tester.pumpAndSettle();

    // The helper is the base equivalent, and it stays a label: the payload keeps
    // the count the receiver wrote.
    expect(find.text('2 BAG = 50 KG'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Record receipt'));
    await tester.pumpAndSettle();

    expect(service.sentLines.single.qty, 2.0);
    expect(service.sentLines.single.poItemId, 11);
  });

  testWidgets('a line from an older server keeps its base-unit meaning', (
    tester,
  ) async {
    final service = await _pump(tester, line: _oldWireLine());

    await tester.tap(find.byKey(const Key('receiving-order-1')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Ordered 10 · already received 0'),
      findsOneWidget,
    );
    expect(find.textContaining(' = '), findsNothing);

    await tester.enterText(find.byKey(const Key('receiving-qty-11')), '2');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record receipt'));
    await tester.pumpAndSettle();

    expect(service.sentLines.single.qty, 2.0);
  });

  // Backend B1 precision guard: the server refuses a count whose base stock
  // cannot be written in hundredths. The client does not re-do that maths — it
  // shows the server's sentence, which names the quantity to record instead.
  testWidgets('a refused receipt shows the server sentence word for word', (
    tester,
  ) async {
    const sentence =
        '0.015 BAG cannot become whole hundredths of base stock: record a '
        'quantity that yields whole hundredths of the base unit, e.g. '
        '0.02 BAG.';
    await _pump(tester, line: _unitLine(), refusal: sentence);

    await tester.tap(find.byKey(const Key('receiving-order-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('receiving-qty-11')), '2');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record receipt'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('whole hundredths of base stock'),
      findsOneWidget,
    );
    expect(find.textContaining('0.02 BAG'), findsOneWidget);
  });

  testWidgets('a narrow window keeps the unit caption readable', (
    tester,
  ) async {
    await _pump(tester, line: _unitLine(), size: const Size(760, 1400));

    await tester.tap(find.byKey(const Key('receiving-order-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('receiving-qty-11')), '2');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('2 BAG = 50 KG'), findsOneWidget);
    expect(find.byType(ErrorBanner), findsNothing);
  });
}
