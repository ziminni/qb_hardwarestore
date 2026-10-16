# Stock Identifier and Location Hint Presentation

**Mode:** grill · **Status:** LOCKED 2026-10-16 · **Phase:** 0 (blocks the staged model swap, step 3)
Surfaced by ruling **R9** during execution of
[Product & Variant Client Model Shape](./02-product-variant-client-model.md).

## The question

`sku` and `storageLocation` are visible columns in the client, but **neither exists in the backend**. Both are
currently carried by `ProductVariant` — a model that must mirror the API exactly. What should those columns
show?

## What was verified first

| Claim | Evidence |
| :--- | :--- |
| `Product` has no SKU | Its only fields are `category`, `brand`, `base_name`, `description`, `image_url`, `is_active` (+ timestamps). |
| `ProductVariant` has no SKU | `product`, `variant_name`, `base_uom`, `min_stock_threshold`, `max_stock_level`, `is_active` (+ timestamps). |
| The only sku-like column in the whole schema is a barcode | `apps/inventory/models.py:128` — `barcode_qr` on `VariantUom`. Nothing else matches `sku`, `part_number`, `model_number`, `item_code`, `product_code`, or `serial`. |
| The SKU strings in the UI are mock inventions | `CEM-HOL-40`, `CEM-REP-40` appear only in `inventory_mock_data.dart`, never in the database. |
| The client has no local storage | `flutter_secure_storage` holds JWT tokens only. No database, no `shared_preferences` — so a client-only field would be in-memory and lost on restart. |

Confirmed against the live API as well: `/products/`, `/variants/` and `/variant-uoms/` return exactly those
field sets, with `barcode_qr` empty (`''`) in every seeded row.

## Options considered

| Option | Trade-off |
| :--- | :--- |
| Drop both columns and the location filter | Nothing invented; but 6 screens lose a column and 20 existing mock location values vanish. |
| Relabel SKU to Barcode (`barcode_qr`), client-only location hint in memory | Honest and cheap; but a hint that resets on every restart is close to useless in a store. |
| **Relabel SKU to Barcode, persist location hints locally** | A hint that survives restarts — genuinely useful. Cost: a new dependency and a local store outside the API. |

## Resolution — LOCKED 2026-10-16

**Two parts.**

### 1. The SKU column becomes a Barcode column

`ProductVariant` loses `sku`; the four tables (`inventory_stock_table`, `inventory_movements_table`,
`inventory_stock_balance_table`, `inventory_low_stock_table`) show `VariantUom.barcodeQr` instead, under the
label **Barcode**. This is the only real identifier in the schema, and it is honestly labelled — the previous
column asserted an identifier that no system owned.

Note: `barcode_qr` is `''` in all seeded data, so the column renders blank until real barcodes are recorded.
That is the honest state, not a bug.

### 2. Storage location becomes a persisted, client-local hint

`storageLocation` leaves `ProductVariant`. It becomes a **client-local hint** — "where we put this in our
store" — persisted with `shared_preferences` so it survives restarts.

Why local rather than removed: the value is real to the store but has no backend home, and adding one would
break this map's `Client-side epic only` invariant. It is explicitly **not** API data; the UI must not present
it as if it were.

Design constraints this locks:

- Keyed by `variantId`. A hint belongs to a variant, not a product.
- Stored under one JSON blob (`stock_location_hints`), not one key per variant.
- Missing/undefined hints are legitimate — the column renders empty, never a placeholder.
- A hint for a variant that no longer exists is inert; it is not garbage-collected, because the client cannot
  know the catalogue's full membership without a fetch.
- No backend change and no new endpoint. If the store ever wants server-side bins, that is a **new map**.

## Consequences for the staged swap

- `sku` and `storageLocation` are deleted from `ProductVariant` at step 4 like the other legacy fields.
- Step 3's reader migration gains one new collaborator: `LocationHintStore`, injected where the location
  column is rendered (`inventory_stock_table`, `inventory_low_stock_table`, `inventory_stock_page`'s filter).
- `pubspec.yaml` gains `shared_preferences`.
