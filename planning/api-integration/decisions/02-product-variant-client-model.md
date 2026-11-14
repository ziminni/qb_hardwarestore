# Product & Variant Client Model Shape

**Mode:** domain-model · **Status:** LOCKED 2026-10-16 · **Opened:** 2026-10-15

## The question

How should the Flutter client represent a Product, its ProductVariants, and stock batches — given that the
current model was written against an API that does not exist?

## Why it matters

`flutter/lib/data/models/product.dart` reads `sku`, `cost_price`, `selling_price`, `current_stock`,
`reorder_level`, `qr_identifier`, `storage_location`, and flattens `base_uom_code` / `variant_name` onto
`Product`. **None of those appear in any backend model or serializer.** The real `ProductSerializer` sends
only `id, category, category_name, brand, brand_name, base_name, description, image_url, is_active, variants,
created_at, updated_at` — variant data arrives nested, and stock quantities live on `InventoryBatch`, not on
the product at all.

This is upstream of Products, Inventory, POS and Requisitions, so it must be settled before any of them is
wired. A sibling file, `data/models/inventory.dart`, holds the `StockAdjustment` shape (its 7 keys match
`StockAdjustmentSerializer` exactly) under a misleading name — so the batch model may not exist yet.

## Needs a domain sketch

The open shape questions, to be worked collaboratively:

- Is `Product` a flat read model with a nested `variants` list, or do `Product` and `ProductVariant` become
  two separate client entities?
- Where does stock quantity live in the client once `/api/v1/batches/` is wired — a field on the variant, a
  separate batch list, or a derived total?
- What happens to `data/models/inventory.dart` — rename it to reflect that it models an adjustment, or split
  batch and adjustment into two files?
- Which screens need variant-level granularity versus product-level display?

## Resolution — LOCKED 2026-10-16

**Option A: mirror the API's four entities, plus one computed `CatalogueItem`.**

Each model mirrors exactly what the API sends, so no model can invent a field:

```dart
// mirrors GET /api/v1/products/  (variants nested)
class Product { ... List<ProductVariant> variants; }
// mirrors GET /api/v1/variants/  (selling_uoms nested)
class ProductVariant { ... List<VariantUom> sellingUoms; }
// mirrors GET /api/v1/variant-uoms/
class VariantUom { ... }
// mirrors GET /api/v1/batches/
class InventoryBatch { ... }
```

And one model that is **computed, never deserialised**:

```dart
class CatalogueItem {
  final Product product;
  final ProductVariant variant;
  final VariantUom uom;
  final double price;
  final double stockOnHand;
}
```

An assembler owns the join: it takes products, variants, uoms and batches and emits catalogue rows. Cost and
stock are per-batch, but price and stock are per-batch too — so the join is unavoidable, and the only question
is whether it happens once or 27 times.

Why not the alternatives:

- **Mirror only, no assembler** — every screen repeats the same price/stock join, so implementations drift and
  nothing can answer "what is this item's price?" in one place.
- **One flattened model** — this is the shape that caused the original defect. A join that misses a source
  yields `0` rather than failing, which is exactly how the client came to render ₱0.00 with nobody noticing.

### Field relocation (what happens to each field today)

| Current field | Becomes |
| :--- | :--- |
| `ProductVariant.variantName` | unchanged — the API sends it |
| `ProductVariant.baseUomCode` | unchanged — the API sends it |
| `ProductVariant.reorderLevel` | `ProductVariant.minStockThreshold` |
| `ProductVariant.qrIdentifier` | `VariantUom.barcodeQr` |
| `ProductVariant.sellingPrice` | `VariantUom.defaultSellingPrice` — rule pending, see [Which Price the POS Charges](./08-pricing-rule.md) |
| `ProductVariant.costPrice` | `InventoryBatch.unitCostLanded` — derivation pending, same decision |
| `ProductVariant.currentStock` | `CatalogueItem.stockOnHand` (sum of `InventoryBatch.currentQty`) |
| `ProductVariant.sku` | **deleted** — no backend counterpart anywhere |
| `ProductVariant.storageLocation` | **deleted** — no backend counterpart anywhere |

`Product` itself needs **no change** — `Product.fromJson` already parses the real payload correctly, including
nested `variants`.

### Files

- `data/models/product.dart` — keep `Product`; rewrite `ProductVariant`; add `VariantUom`.
- New `data/models/inventory_batch.dart`.
- `data/models/inventory.dart` — holds `StockAdjustment` under a misleading name; rename it or split it.
- New catalogue assembler beside the repositories.

### A consequence that must not be lost

The `?? 0` fallbacks are what hid this defect for so long. The rewritten `fromJson` implementations should
**not** swallow missing required fields — a missing `variant_name` should throw during development rather than
render as empty or zero.

### Spawned a new decision

Research surfaced a question the map did not have — which price the POS charges when
`VariantUom.default_selling_price` (₱315.00) and `InventoryBatch.batch_selling_price` (₱180.00) disagree for the
same variant in seed data, and how "current cost" derives from a per-batch `unit_cost_landed`. Filed as
[Which Price the POS Charges](./08-pricing-rule.md).
