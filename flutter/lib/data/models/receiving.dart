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

class GoodsReceiptRecord {
  const GoodsReceiptRecord({
    required this.id,
    required this.poId,
    required this.deliveryReceiptNo,
    required this.batches,
  });

  final int id;
  final int poId;
  final String deliveryReceiptNo;
  final List<InventoryBatch> batches;

  factory GoodsReceiptRecord.fromJson(Map<String, dynamic> json) {
    final batches = json['batches'];
    if (batches is! List) {
      throw FormatException('Missing required list field "batches"');
    }
    return GoodsReceiptRecord(
      id: intField(json, 'id'),
      poId: intField(json, 'po'),
      deliveryReceiptNo: stringField(json, 'delivery_receipt_no'),
      batches: batches
          .map((b) => InventoryBatch.fromJson(b as Map<String, dynamic>))
          .toList(),
    );
  }
}
