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
PurchaseOrderRecord _order({
  int id = 1,
  String status = 'ORDERED',
  double receivedQty = 0,
}) => PurchaseOrderRecord(
  id: id,
  supplierId: 2,
  status: status,
  notes: '',
  items: [
    PurchaseOrderItem(
      id: id * 10 + 1,
      poId: id,
      variantId: 8,
      variantName: 'Portland 40kg',
      orderedQty: 10,
      unitCost: 50,
      receivedQty: receivedQty,
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
  // The Receive hand-off is a static, so one test leaving it set would bend the
  // next test's first load.
  tearDown(() => ReceivingViewmodel.pendingPurchaseOrderId = null);

  testWidgets('purchase orders render and a receipt can be recorded', (
    tester,
  ) async {
    final service = await _pump(tester);

    expect(find.byKey(const Key('receiving-order-1')), findsOneWidget);

    await tester.tap(find.byKey(const Key('receiving-order-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('receiving-qty-11')), '4');
    // The Record button is enabled by what was counted, so it needs the frame
    // that reads the new quantity.
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record receipt'));
    await tester.pumpAndSettle();

    expect(service.recordCalls, 1);
    expect(find.textContaining('Receipt #5'), findsOneWidget);
  });

  testWidgets('after processing the button is gone, not re-tappable', (
    tester,
  ) async {
    await _pump(tester);

    await tester.tap(find.byKey(const Key('receiving-order-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('receiving-qty-11')), '4');
    // The Record button is enabled by what was counted, so it needs the frame
    // that reads the new quantity.
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record receipt'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Process into stock'));
    await tester.pumpAndSettle();

    expect(
      find.widgetWithText(FilledButton, 'Process into stock'),
      findsNothing,
    );
    expect(find.textContaining('batch'), findsWidgets);
  });

  testWidgets('processing a receipt offers the process action', (tester) async {
    final service = await _pump(tester);

    await tester.tap(find.byKey(const Key('receiving-order-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('receiving-qty-11')), '4');
    // The Record button is enabled by what was counted, so it needs the frame
    // that reads the new quantity.
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Record receipt'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Process into stock'));
    await tester.pumpAndSettle();

    expect(service.processCalls, 1);
  });

  testWidgets('the three steps are visible and Process waits for Record', (
    tester,
  ) async {
    final service = await _pump(tester);

    // K8: the plan's whole point is that recording and processing are TWO
    // confirmations, and the old screen only showed the second one after the
    // first had already been pressed.
    expect(find.text('1 Pick a purchase order'), findsOneWidget);
    expect(find.text('2 Record receipt'), findsOneWidget);
    expect(find.text('3 Process into stock'), findsOneWidget);

    // The guard is visible and dead, not absent: a button that does not exist
    // cannot tell the reader that processing is the later step.
    final process = find.widgetWithText(FilledButton, 'Process into stock');
    expect(process, findsOneWidget);
    expect(tester.widget<FilledButton>(process).onPressed, isNull);
    await tester.tap(process, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(service.processCalls, 0);
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
    // One failure, with the way out of it.
    expect(find.text('Retry'), findsOneWidget);
    expect(
      find.textContaining('No order is waiting to be received'),
      findsNothing,
    );
  });

  testWidgets('the whole flow: pick, count, record, process, then labels', (
    tester,
  ) async {
    final service = await _pump(tester);

    await tester.tap(find.byKey(const Key('receiving-order-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('receiving-qty-11')), '4');
    await tester.pumpAndSettle();

    // record/ moves the order's received quantity server-side, so the panel has
    // to show the SERVER's copy, not the one it was opened from.
    service.orders = [_order(status: 'PARTIAL', receivedQty: 4)];
    await tester.tap(find.widgetWithText(FilledButton, 'Record receipt'));
    await tester.pumpAndSettle();
    expect(find.text('PO-1 · PARTIAL'), findsOneWidget);
    expect(find.textContaining('4 received'), findsOneWidget);

    // process/ is where the server flips the status to COMPLETE.
    service.orders = [_order(status: 'COMPLETE', receivedQty: 10)];
    await tester.tap(find.widgetWithText(FilledButton, 'Process into stock'));
    await tester.pumpAndSettle();
    expect(find.text('PO-1 · COMPLETE'), findsOneWidget);
    expect(
      find.textContaining('1 batch created from receipt #5'),
      findsOneWidget,
    );
    // Labels are offered only for the delivery this screen just created.
    expect(find.text('Print labels for this delivery'), findsOneWidget);
  });

  testWidgets('Receive on Purchases opens Receiving with that order picked', (
    tester,
  ) async {
    // What the Purchases row's Receive action parks before it navigates: the
    // receiving route carries no query string, so the choice rides over here.
    ReceivingViewmodel.pendingPurchaseOrderId = 2;

    await _pump(tester, orders: [_order(), _order(id: 2)]);

    expect(find.text('PO-2 · ORDERED'), findsOneWidget);
    // Taken once: a later visit from the sidebar must not reopen on it.
    expect(ReceivingViewmodel.pendingPurchaseOrderId, isNull);
  });

  test(
    'a FAILED first load drops the Receive hand-off instead of keeping it',
    () async {
      // The hand-off is parked before navigating, so the load that follows is the
      // one that must eat it. It used to be taken only on a successful read, which
      // left it parked across a failed visit, a sign-out and a role switch: the
      // next person to open Receiving opened preselected on somebody else's PO.
      ReceivingViewmodel.pendingPurchaseOrderId = 2;
      final service = _StubInventoryService()
        ..failure = 'Cannot connect to the BuildPro server.';
      final viewmodel = ReceivingViewmodel(service: service);

      await viewmodel.load();

      expect(viewmodel.loadError, 'Cannot connect to the BuildPro server.');
      expect(ReceivingViewmodel.pendingPurchaseOrderId, isNull);

      // And the later, successful load opens on nothing: the intent belonged to
      // the visit that failed.
      service
        ..failure = null
        ..orders = [_order(), _order(id: 2)];
      await viewmodel.load();
      expect(viewmodel.selected, isNull);
    },
  );

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
