import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/repositories/auth_repository.dart';
import 'package:client/data/services/auth_service.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/features/auth/viewmodels/auth_viewmodel.dart';
import 'package:client/features/inventory/viewmodels/receiving_viewmodel.dart';
import 'package:client/features/inventory/views/inventory_receiving_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

Widget _app(Widget child) => ChangeNotifierProvider<AuthViewmodel>.value(
  value: AuthViewmodel(AuthRepository(AuthService())),
  child: MaterialApp(home: child),
);

class _StubInventoryService extends InventoryService {
  _StubInventoryService() : super();

  List<PurchaseOrderRecord> orders = const [];
  int recordCalls = 0;
  int processCalls = 0;

  /// Refuse the purchase-order read, the way a contract break or a dead server
  /// does once the service has mapped it.
  String? failure;

  @override
  Future<List<PurchaseOrderRecord>> fetchPurchaseOrders() async {
    final error = failure;
    if (error != null) throw InventoryServiceException(error);
    return orders;
  }

  @override
  Future<GoodsReceiptRecord> createReceipt({
    required int poId,
    required List<ReceiptLine> items,
    String deliveryReceiptNo = '',
  }) async {
    recordCalls++;
    return GoodsReceiptRecord(
      id: 5,
      poId: poId,
      deliveryReceiptNo: deliveryReceiptNo,
      batches: const [],
    );
  }

  List<GoodsReceiptRecord> receipts = const [];

  @override
  Future<List<GoodsReceiptRecord>> fetchGoodsReceipts() async => receipts;

  @override
  Future<List<InventoryBatch>> processReceipt(int receiptId) async {
    processCalls++;
    return const [
      InventoryBatch(
        id: 21,
        variantId: 8,
        receiptId: 5,
        initialQty: 4,
        currentQty: 4,
        unitCostLanded: 50,
        markupPercentage: 0,
        batchSellingPrice: 50,
        expirationDate: null,
        createdAt: null,
      ),
    ];
  }
}

/// ORDERED, not DRAFT: the screen now lists only the orders the server will let
/// it receive (ORDERED / PARTIAL). A DRAFT one answers 400 PO_NOT_ORDERED, so
/// offering it was a button that could only produce a refusal.
PurchaseOrderRecord _order({String status = 'ORDERED'}) => PurchaseOrderRecord(
  id: 1,
  supplierId: 2,
  status: status,
  notes: '',
  items: const [
    PurchaseOrderItem(
      id: 11,
      poId: 1,
      variantId: 8,
      variantName: 'Portland 40kg',
      orderedQty: 10,
      unitCost: 50,
      receivedQty: 0,
    ),
  ],
);

GoodsReceiptRecord _receipt({bool processed = false}) => GoodsReceiptRecord(
  id: 7,
  poId: 1,
  deliveryReceiptNo: 'DR-9001',
  batches: const [],
  receivedByName: 'Ana Lopez',
  receiveDate: DateTime(2026, 10, 25, 9, 30),
  lines: const [
    GoodsReceiptLine(id: 1, poItemId: 11, variantName: 'Portland 40kg', qty: 4),
  ],
  processedAt: processed ? DateTime(2026, 10, 25, 9, 45) : null,
);

void _sizeUp(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<_StubInventoryService> _pump(
  WidgetTester tester, {
  List<PurchaseOrderRecord>? orders,
  List<GoodsReceiptRecord>? receipts,
}) async {
  _sizeUp(tester);
  final service = _StubInventoryService()
    ..orders = orders ?? [_order()]
    ..receipts = receipts ?? const [];
  await tester.pumpWidget(
    _app(
      InventoryReceivingPage(viewmodel: ReceivingViewmodel(service: service)),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  testWidgets('purchase orders render and a receipt can be recorded', (
    tester,
  ) async {
    final service = await _pump(tester);

    expect(find.textContaining('PO-1'), findsOneWidget);

    await tester.tap(find.textContaining('PO-1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('receiving-qty-11')), '4');
    await tester.tap(find.text('Record receipt'));
    await tester.pumpAndSettle();

    expect(service.recordCalls, 1);
    expect(find.textContaining('Receipt #5'), findsOneWidget);
  });

  testWidgets('after processing the button is gone, not re-tappable', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.textContaining('PO-1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('receiving-qty-11')), '4');
    await tester.tap(find.text('Record receipt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Process into stock'));
    await tester.pumpAndSettle();

    expect(find.text('Process into stock'), findsNothing);
    expect(find.textContaining('batch'), findsWidgets);
  });

  testWidgets('processing a receipt offers the process action', (tester) async {
    final service = await _pump(tester);

    await tester.tap(find.textContaining('PO-1'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('receiving-qty-11')), '4');
    await tester.tap(find.text('Record receipt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Process into stock'));
    await tester.pumpAndSettle();

    expect(service.processCalls, 1);
  });

  testWidgets('a failed load reports the error, not "no order is waiting"', (
    tester,
  ) async {
    // F2 sweep: the receiving workspace has a spinner and an error line, but its
    // empty copy still spoke for a fetch that never succeeded.
    _sizeUp(tester);
    final service = _StubInventoryService()
      ..failure = 'Cannot connect to the BuildPro server.';
    await tester.pumpWidget(
      _app(
        InventoryReceivingPage(viewmodel: ReceivingViewmodel(service: service)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Cannot connect'), findsOneWidget);
    expect(
      find.textContaining('No order is waiting to be received'),
      findsNothing,
    );
  });

  testWidgets('a DRAFT order is not offered for receiving', (tester) async {
    await _pump(tester, orders: [_order(status: 'DRAFT')]);

    expect(find.textContaining('PO-1'), findsNothing);
    expect(
      find.textContaining(
        'Only ORDERED or PARTIAL purchase orders can be received',
      ),
      findsOneWidget,
    );
  });

  testWidgets('received deliveries list the server history and open a sheet', (
    tester,
  ) async {
    await _pump(tester, receipts: [_receipt(processed: true)]);

    await tester.tap(find.text('Received deliveries'));
    await tester.pumpAndSettle();

    expect(find.text('PO-1'), findsOneWidget);
    expect(find.text('DR-9001'), findsOneWidget);
    expect(find.text('Ana Lopez'), findsOneWidget);
    expect(find.text('In stock'), findsOneWidget);

    await tester.tap(find.byTooltip('View delivery'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Delivery #7'), findsOneWidget);
    expect(find.text('Portland 40kg'), findsWidgets);
    // Appending a delivery is the only write: the sheet offers no edit.
    expect(find.text('Close'), findsOneWidget);
  });
}
