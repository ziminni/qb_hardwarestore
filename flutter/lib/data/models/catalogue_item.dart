import 'package:client/data/models/product.dart';
import 'package:client/data/models/variant_uom.dart';

/// One renderable row of the catalogue.
///
/// **Computed, never deserialised.** No endpoint returns this shape: the API
/// splits it across three resources, and stock lives in a fourth.
///
/// | field | real source |
/// | :--- | :--- |
/// | `product` | `GET /api/v1/products/` |
/// | `variant` | nested `variants[]`, or `GET /api/v1/variants/` |
/// | `uom` | nested `selling_uoms[]`, or `GET /api/v1/variant-uoms/` |
/// | `price` | `uom.defaultSellingPrice` — the **charged** price (decision 08) |
/// | `stockOnHand` | sum of `GET /api/v1/stock-on-hand/` qty rows (Phase 9 F1) |
///
/// Decision: `planning/api-integration/decisions/02-product-variant-client-model.md`.
class CatalogueItem {
  const CatalogueItem({
    required this.product,
    required this.variant,
    required this.uom,
    required this.price,
    required this.stockOnHand,
  });

  final Product product;
  final ProductVariant variant;

  /// The selling unit this row prices. Every row has one — a variant with no
  /// selling unit has no chargeable price and is excluded from the catalogue.
  final VariantUom uom;

  /// What the customer is charged. Never `InventoryBatch.batchSellingPrice`.
  final double price;

  /// Quantity available: the TOTAL across the variant's shelves, from the
  /// server's `/stock-on-hand/` rows. Not a batch sum (Phase 9 F1).
  final double stockOnHand;

  /// True when stock has fallen to or below the variant's configured threshold.
  bool get isLowStock =>
      stockOnHand > 0 && stockOnHand <= variant.minStockThreshold;

  bool get isOutOfStock => stockOnHand <= 0;

  /// Display string, e.g. `Circuit Breaker 20A 1-pole`.
  String get displayName => '${product.baseName} ${variant.variantName}';
}
