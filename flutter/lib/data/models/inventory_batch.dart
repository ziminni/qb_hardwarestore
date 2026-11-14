import 'package:client/data/models/json_field.dart';

/// One FIFO stock lot for a variant — mirrors `GET /api/v1/batches/`.
///
/// Stock lives here, not on the product or the variant: neither
/// `GET /api/v1/products/` nor `GET /api/v1/variants/` exposes a quantity
/// (verified against the running API). A catalogue row's stock on hand is
/// therefore the sum of [currentQty] across the batches for that variant.
///
/// Cost is per batch, so there is no single "cost" for a variant; the display
/// rule is the latest batch's [unitCostLanded], labelled as such.
/// Decision: `planning/api-integration/decisions/08-pricing-rule.md`.
class InventoryBatch {
  const InventoryBatch({
    required this.id,
    required this.variantId,
    required this.receiptId,
    required this.initialQty,
    required this.currentQty,
    required this.unitCostLanded,
    required this.markupPercentage,
    required this.batchSellingPrice,
    required this.expirationDate,
    required this.createdAt,
  });

  final int id;
  final int variantId;
  final int receiptId;
  final double initialQty;

  /// Remaining quantity in this lot — what FIFO deducts from.
  final double currentQty;

  final double unitCostLanded;
  final double markupPercentage;

  /// This batch's own selling price. **Display only** — never charged.
  /// The charged price is `VariantUom.defaultSellingPrice`.
  final double batchSellingPrice;

  final DateTime? expirationDate;
  final DateTime? createdAt;

  factory InventoryBatch.fromJson(Map<String, dynamic> json) {
    return InventoryBatch(
      id: intField(json, 'id'),
      variantId: intField(json, 'variant'),
      receiptId: intField(json, 'receipt'),
      initialQty: decimalField(json, 'initial_qty'),
      currentQty: decimalField(json, 'current_qty'),
      unitCostLanded: decimalField(json, 'unit_cost_landed'),
      markupPercentage: decimalField(json, 'markup_percentage'),
      batchSellingPrice: decimalField(json, 'batch_selling_price'),
      expirationDate: nullableDateField(json, 'expiration_date'),
      createdAt: nullableDateField(json, 'created_at'),
    );
  }
}
