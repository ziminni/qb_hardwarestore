# UOM and Price Authority

**Status:** Locked 2026-10-24 (Grill). **Phase:** 1.

## Decision
- Client sends `variant_uom_id` + selling-unit `qty`. Server computes `base_qty = qty × VariantUOM.conversion_factor` and passes `base_qty` to `allocate_fifo`. `SalesItem` keeps selling qty + UOM for the receipt.
- Server sets `unit_price = VariantUOM.default_selling_price`. Any client `unit_price` is ignored (not an error, so older clients still work). Discounts are out of scope.
- Same rule in `release_materials()` and held-cart `complete`.

## Why
Today `process_sale()` passes raw `qty` to FIFO — selling 1 box (CF 12) deducts 1 piece. Client prices are trusted, so a tampered request or a swapped barcode label could set any price.

## Security / RED tests
- CF 12 sale of 1 deducts 12 base units.
- Fractional CF (e.g. 0.5 m) rounds per `DecimalField` precision; insufficient-stock compares `base_qty`.
- Forged `unit_price: 0.01` → recorded price = default price.
- Inactive VariantUOM / variant → 400.
