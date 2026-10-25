import 'package:client/data/models/inventory_batch.dart';
import 'package:client/data/models/json_field.dart';

/// Server nouns behind the receiving screen (decision 17).
///
/// Shapes verified against `backend_django/apps/inventory/{serializers,views}.py`.
/// Distinct from the suppliers feature's mock `PurchaseOrder`: that one is
/// memory-only demo data, while these rows come from `/api/v1/purchase-orders/`.
class PurchaseOrderItem {
  const PurchaseOrderItem({
    required this.id,
    required this.poId,
    required this.variantId,
    required this.variantName,
    required this.orderedQty,
    required this.unitCost,
    required this.receivedQty,
  });

  final int id;
  final int poId;
  final int variantId;
  final String variantName;
  final double orderedQty;
  final double unitCost;
  final double receivedQty;

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) =>
      PurchaseOrderItem(
        id: intField(json, 'id'),
        poId: intField(json, 'po'),
        variantId: intField(json, 'variant'),
        variantName: stringField(json, 'variant_name'),
        orderedQty: decimalField(json, 'ordered_qty'),
        unitCost: decimalField(json, 'unit_cost'),
        receivedQty: decimalField(json, 'received_qty'),
      );
}

class PurchaseOrderRecord {
  const PurchaseOrderRecord({
    required this.id,
    required this.supplierId,
    required this.status,
    required this.notes,
    required this.items,
  });

  final int id;
  final int supplierId;
  final String status;
  final String notes;
  final List<PurchaseOrderItem> items;

  /// Only an ORDERED or PARTIAL order can be received — the server refuses a
  /// DRAFT with `PO_NOT_ORDERED` and a COMPLETE/CANCELLED one with
  /// `PO_NOT_RECEIVABLE`. The receiving list therefore shows these two states
  /// only, so the screen cannot offer a delivery the server will reject.
  bool get isReceivable => status == 'ORDERED' || status == 'PARTIAL';

  factory PurchaseOrderRecord.fromJson(Map<String, dynamic> json) {
    final items = json['items'];
    if (items is! List) {
      throw FormatException('Missing required list field "items"');
    }
    return PurchaseOrderRecord(
      id: intField(json, 'id'),
      supplierId: intField(json, 'supplier'),
      status: stringField(json, 'status'),
      notes: stringField(json, 'notes'),
      items: items
          .map((i) => PurchaseOrderItem.fromJson(i as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// One received quantity line the client sends when recording a receipt.
class ReceiptLine {
  const ReceiptLine({required this.poItemId, required this.qty});

  final int poItemId;
  final double qty;

  Map<String, dynamic> toJson() => {'po_item': poItemId, 'qty': qty};
}

/// One delivered quantity as the server reports it back (`GoodsReceiptItem`).
///
/// `qty` is what THIS receipt delivered, not the order's running total, and the
/// variant name is denormalised into the row so a history list needs one request
/// rather than one per line.
class GoodsReceiptLine {
  const GoodsReceiptLine({
    required this.id,
    required this.poItemId,
    required this.variantName,
    required this.qty,
  });

  final int id;
  final int poItemId;
  final String variantName;
  final double qty;

  factory GoodsReceiptLine.fromJson(Map<String, dynamic> json) =>
      GoodsReceiptLine(
        id: intField(json, 'id'),
        poItemId: intField(json, 'po_item'),
        variantName: stringField(json, 'variant_name'),
        qty: decimalField(json, 'qty'),
      );
}

/// A goods receipt: the create answer and one row of `GET /goods-receipts/`.
///
/// One model for both because it is one serializer. The history-only fields are
/// tolerant (`batches` absent → empty, `processed_at` absent → null) so a create
/// response and a list row are both readable without a second class that could
/// drift from the wire.
class GoodsReceiptRecord {
  const GoodsReceiptRecord({
    required this.id,
    required this.poId,
    required this.deliveryReceiptNo,
    required this.batches,
    this.receivedByName = '',
    this.receiveDate,
    this.notes = '',
    this.lines = const [],
    this.processedAt,
  });

  final int id;
  final int poId;
  final String deliveryReceiptNo;
  final List<InventoryBatch> batches;

  /// Who booked the delivery in — the server's `received_by_name`.
  final String receivedByName;
  final DateTime? receiveDate;
  final String notes;
  final List<GoodsReceiptLine> lines;

  /// Null until `process/` turned the lines into FIFO batches.
  final DateTime? processedAt;

  bool get isProcessed => processedAt != null;

  double get totalQty => lines.fold(0, (sum, line) => sum + line.qty);

  factory GoodsReceiptRecord.fromJson(Map<String, dynamic> json) {
    return GoodsReceiptRecord(
      id: intField(json, 'id'),
      poId: intField(json, 'po'),
      deliveryReceiptNo: stringField(json, 'delivery_receipt_no'),
      batches: (json['batches'] as List<dynamic>? ?? const [])
          .map((b) => InventoryBatch.fromJson(b as Map<String, dynamic>))
          .toList(),
      receivedByName: json['received_by_name'] as String? ?? '',
      receiveDate: nullableDateField(json, 'receive_date'),
      notes: json['notes'] as String? ?? '',
      lines: (json['lines'] as List<dynamic>? ?? const [])
          .map(
            (line) => GoodsReceiptLine.fromJson(line as Map<String, dynamic>),
          )
          .toList(),
      processedAt: nullableDateField(json, 'processed_at'),
    );
  }
}
