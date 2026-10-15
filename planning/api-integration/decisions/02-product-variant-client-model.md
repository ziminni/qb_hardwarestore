# Product & Variant Client Model Shape

**Mode:** domain-model · **Status:** OPEN · **Opened:** 2026-10-15

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

## Resolution

_Unresolved._
