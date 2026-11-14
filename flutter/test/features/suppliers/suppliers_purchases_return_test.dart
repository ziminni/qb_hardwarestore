// Phase 8 F2 (decision 20): what the purchase-order viewmodel owes the return
// dialog.
//
// Three wire facts are pinned here, because a widget test cannot see them:
//   * only PROCESSED deliveries of THIS order come back — an unprocessed receipt
//     created no batches, so a return off it would be refused;
//   * the quantities go out as 2 dp strings, like a payment amount: a double can
//     serialize as `2.0000000000000004` and the server refuses a fraction of a
//     whole package unit;
//   * a refusal is a sentence for a person, never a thrown exception the dialog
//     would have to interpret.

import 'dart:convert';

import 'package:client/core/network/api_client.dart';
import 'package:client/data/models/receiving.dart';
import 'package:client/data/models/supplier_returns.dart';
import 'package:client/data/repositories/inventory_repository.dart';
import 'package:client/data/repositories/payables_repository.dart';
import 'package:client/data/services/inventory_service.dart';
import 'package:client/data/services/payables_service.dart';
import 'package:client/features/suppliers/viewmodels/suppliers_purchases_viewmodel.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.respond);

  final ResponseBody Function(RequestOptions options) respond;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async => respond(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonPage(Object body) => ResponseBody.fromString(
  jsonEncode(body),
  200,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

/// One `GET /goods-receipts/` row as DRF serialises it.
Map<String, dynamic> _receiptRow({required int id, required int poId}) => {
  'id': id,
  'po': poId,
  'received_by': 3,
  'received_by_name': 'Stock Manager',
  'receive_date': '2026-11-12',
  'delivery_receipt_no': 'DR-$id',
  'notes': '',
  'batches': [],
  'lines': [
    {
      'id': id * 10,
      'po_item': 1,
      'variant_name': 'Portland Cement 40kg',
      'qty': '10.00',
    },
  ],
  'processed_at': '2026-11-12T09:00:00Z',
  'created_at': '2026-11-12T08:00:00Z',
};

GoodsReceiptRecord _receipt({
  required int id,
  required int poId,
  bool processed = true,
}) => GoodsReceiptRecord(
  id: id,
  poId: poId,
  deliveryReceiptNo: 'DR-$id',
  batches: const [],
  receiveDate: DateTime(2026, 11, 12),
  processedAt: processed ? DateTime(2026, 11, 12) : null,
  lines: const [
    GoodsReceiptLine(
      id: 11,
      poItemId: 1,
      variantName: 'Portland Cement 40kg',
      qty: 10,
    ),
  ],
);

SupplierReturnableLine _returnable({
  int receiptLineId = 11,
  double returnable = 3,
}) => SupplierReturnableLine(
  receiptLineId: receiptLineId,
  variantId: 1,
  variantName: 'Portland Cement 40kg',
  unit: 'BAG',
  delivered: 10,
  returned: 0,
  returnable: returnable,
);

class _StubInventory extends InventoryRepository {
  _StubInventory({this.receipts = const []}) : super(InventoryService());

  List<GoodsReceiptRecord> receipts;
  String? failure;

  @override
  Future<List<GoodsReceiptRecord>> loadGoodsReceipts() async {
    final failure = this.failure;
    if (failure != null) throw InventoryServiceException(failure);
    return receipts;
  }
}

class _StubPayables extends PayablesRepository {
  List<SupplierReturnableLine> lines = const [];
  String? returnableFailure;
  String? returnFailure;
  SupplierReturn? recorded;
  int returnableFor = 0;
  int sentReceiptId = 0;
  String sentReason = '';
  List<Map<String, dynamic>> sentLines = const [];

  @override
  Future<List<SupplierReturnableLine>> fetchReturnable(int receiptId) async {
    returnableFor = receiptId;
    final failure = returnableFailure;
    if (failure != null) throw PayablesServiceException(failure);
    return lines;
  }

  @override
  Future<SupplierReturn> createReturn({
    required int receiptId,
    required String reason,
    required List<Map<String, dynamic>> lines,
  }) async {
    sentReceiptId = receiptId;
    sentReason = reason;
    sentLines = lines;
    final failure = returnFailure;
    if (failure != null) throw PayablesServiceException(failure);
    return recorded!;
  }
}

SupplierReturn _recordedReturn() => SupplierReturn(
  id: 7,
  receiptId: 5,
  supplierId: 2,
  supplierName: 'Cebu Steel Works',
  purchaseOrderId: 41,
  billId: 12,
  reason: 'Damaged in transit',
  createdByName: 'Ana Lopez',
  createdAt: DateTime(2026, 11, 14),
  creditNoteNumber: 'CN-20261114-0001',
  creditNoteTotal: 300,
  creditNoteRemaining: 100,
  lines: const [],
);

void main() {
  test(
    'only processed deliveries of this order can be returned from',
    () async {
      final inventory = _StubInventory(
        receipts: [
          _receipt(id: 5, poId: 41),
          _receipt(id: 6, poId: 41, processed: false),
          _receipt(id: 7, poId: 43),
        ],
      );
      final viewmodel = SuppliersPurchasesViewmodel(inventory: inventory);

      final loaded = await viewmodel.processedReceipts(41);

      expect(loaded.error, isNull);
      expect(loaded.receipts.map((receipt) => receipt.id), [5]);
    },
  );

  test(
    'an unreadable receipt list says so instead of showing an empty order',
    () async {
      final viewmodel = SuppliersPurchasesViewmodel(
        inventory: _StubInventory()
          ..failure = 'The goods receipts could not be read.',
      );

      final loaded = await viewmodel.processedReceipts(41);

      expect(loaded.receipts, isEmpty);
      expect(loaded.error, 'The goods receipts could not be read.');
    },
  );

  test('the returnable lines come from the receipt that was picked', () async {
    final payables = _StubPayables()..lines = [_returnable()];
    final viewmodel = SuppliersPurchasesViewmodel(payables: payables);

    final loaded = await viewmodel.returnableFor(5);

    expect(payables.returnableFor, 5);
    expect(loaded.error, isNull);
    expect(loaded.lines.single.returnable, 3);
  });

  test('a returnable load failure carries the server sentence', () async {
    final viewmodel = SuppliersPurchasesViewmodel(
      payables: _StubPayables()
        ..returnableFailure = 'The returnable quantities could not be loaded.',
    );

    final loaded = await viewmodel.returnableFor(5);

    expect(loaded.lines, isEmpty);
    expect(loaded.error, 'The returnable quantities could not be loaded.');
  });

  test('a return is sent with 2 dp quantities and a receipt id', () async {
    final payables = _StubPayables()..recorded = _recordedReturn();
    final viewmodel = SuppliersPurchasesViewmodel(payables: payables);

    final outcome = await viewmodel.returnToSupplier(
      receiptId: 5,
      reason: '  Damaged in transit  ',
      lines: [(receiptLineId: 11, qty: 2)],
    );

    expect(outcome.refusal, isNull);
    expect(outcome.recorded?.creditNoteNumber, 'CN-20261114-0001');
    expect(payables.sentReceiptId, 5);
    expect(payables.sentReason, 'Damaged in transit');
    expect(payables.sentLines, [
      {'receipt_line': 11, 'qty': '2.00'},
    ]);
  });

  test('a refusal comes back as a sentence, never as a throw', () async {
    final viewmodel = SuppliersPurchasesViewmodel(
      payables: _StubPayables()
        ..returnFailure =
            'RETURN_EXCEEDS_RECEIPT: only 2.00 BAG left on this line.',
    );

    final outcome = await viewmodel.returnToSupplier(
      receiptId: 5,
      reason: 'Damaged in transit',
      lines: [(receiptLineId: 11, qty: 3)],
    );

    expect(outcome.recorded, isNull);
    expect(
      outcome.refusal,
      'RETURN_EXCEEDS_RECEIPT: only 2.00 BAG left on this line.',
    );
  });

  // F2 fix round: `GET /goods-receipts/` is paginated (DRF `PAGE_SIZE` 50,
  // newest first). Reading one page hid an older-but-valid order's deliveries,
  // so the dialog stated "No processed deliveries to return from." about an
  // order that has several. The list is read to its end.
  test('a delivery for an old order is found past the first page', () async {
    // 50 newer deliveries of another order fill page 1; the order under test
    // is only on page 2, exactly as DRF's newest-first paging puts it.
    ApiClient.instance.init();
    final pageRequests = <Object?>[];
    ApiClient.instance.dio.httpClientAdapter = _FakeAdapter((options) {
      final page = options.queryParameters['page'] ?? 1;
      pageRequests.add(page);
      if (page == 1) {
        return _jsonPage({
          'count': 51,
          'next': 'http://localhost/api/v1/goods-receipts/?page=2',
          'previous': null,
          'results': [
            for (var id = 100; id < 150; id++) _receiptRow(id: id, poId: 90),
          ],
        });
      }
      return _jsonPage({
        'count': 51,
        'next': null,
        'previous': 'http://localhost/api/v1/goods-receipts/',
        'results': [_receiptRow(id: 7, poId: 41)],
      });
    });

    final viewmodel = SuppliersPurchasesViewmodel(
      inventory: InventoryRepository(InventoryService()),
    );

    final loaded = await viewmodel.processedReceipts(41);

    expect(loaded.error, isNull);
    expect(pageRequests, [1, 2]);
    expect(loaded.receipts.map((receipt) => receipt.id), [7]);
  });
}
