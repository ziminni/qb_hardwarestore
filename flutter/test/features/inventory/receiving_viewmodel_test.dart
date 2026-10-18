import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/features/inventory/viewmodels/receiving_viewmodel.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubInventoryService extends InventoryService {
  _StubInventoryService() : super();

  List<PurchaseOrderRecord> orders = const [];
  int fetchCalls = 0;
  int recordCalls = 0;
  int processCalls = 0;
  List<ReceiptLine>? lastLines;
  String? failure;

  @override
  Future<List<PurchaseOrderRecord>> fetchPurchaseOrders() async {
    fetchCalls++;
    final failure = this.failure;
    if (failure != null) throw InventoryServiceException(failure);
    return orders;
  }

  @override
  Future<GoodsReceiptRecord> createReceipt({
    required int poId,
    required List<ReceiptLine> items,
    String deliveryReceiptNo = '',
  }) async {
    recordCalls++;
    lastLines = items;
    final failure = this.failure;
    if (failure != null) throw InventoryServiceException(failure);
    return GoodsReceiptRecord(id: 5, poId: poId, deliveryReceiptNo: deliveryReceiptNo, batches: const []);
  }

  @override
  Future<List<InventoryBatch>> processReceipt(int receiptId) async {
    processCalls++;
    final failure = this.failure;
    if (failure != null) throw InventoryServiceException(failure);
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

void main() {
  late _StubInventoryService service;
  late ReceivingViewmodel viewmodel;

  setUp(() {
    service = _StubInventoryService();
    viewmodel = ReceivingViewmodel(service: service);
  });

  test('loads the purchase orders on start', () async {
    service.orders = [_order()];

    await viewmodel.load();

    expect(viewmodel.orders, hasLength(1));
    expect(viewmodel.loadError, isNull);
  });

  test('a failed load names the failure and keeps old rows', () async {
    service.orders = [_order()];
    await viewmodel.load();
    service.orders = const [];
    service.failure = 'Cannot connect to the BuildPro server.';

    await viewmodel.load();

    expect(viewmodel.loadError, contains('Cannot connect'));
    expect(viewmodel.orders, hasLength(1));
  });

  test('recording posts one line per order item with the entered quantities', () async {
    service.orders = [_order()];
    await viewmodel.load();

    viewmodel.select(viewmodel.orders.single);
    viewmodel.setQty(11, 4);
    final ok = await viewmodel.recordReceipt();

    expect(ok, isTrue);
    expect(service.recordCalls, 1);
    expect(service.lastLines, hasLength(1));
    expect(viewmodel.lastReceiptId, 5);
  });
}
