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

  @override
  Future<List<PurchaseOrderRecord>> fetchPurchaseOrders() async => orders;

  @override
  Future<GoodsReceiptRecord> createReceipt({
    required int poId,
    required List<ReceiptLine> items,
    String deliveryReceiptNo = '',
  }) async {
    recordCalls++;
    return GoodsReceiptRecord(id: 5, poId: poId, deliveryReceiptNo: deliveryReceiptNo, batches: const []);
  }

  @override
  Future<List<InventoryBatch>> processReceipt(int receiptId) async {
    processCalls++;
    return const [];
  }
}

PurchaseOrderRecord _order() => const PurchaseOrderRecord(
  id: 1,
  supplierId: 2,
  status: 'DRAFT',
  notes: '',
  items: [
    PurchaseOrderItem(id: 11, poId: 1, variantId: 8, variantName: 'Portland 40kg', orderedQty: 10, unitCost: 50, receivedQty: 0),
  ],
);

void _sizeUp(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<_StubInventoryService> _pump(WidgetTester tester) async {
  _sizeUp(tester);
  final service = _StubInventoryService()..orders = [_order()];
  await tester.pumpWidget(
    _app(InventoryReceivingPage(viewmodel: ReceivingViewmodel(service: service))),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  testWidgets('purchase orders render and a receipt can be recorded', (tester) async {
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
}
