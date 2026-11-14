# Phase 1 Live Data Home and Mock Retention

**Mode:** grill · **Status:** LOCKED 2026-10-16 · **Phase:** 1
Resolves where Phase 1's live API data lives, and what stays mocked while the rest of Phase 0's store is wired.

## The question

Phase 1 is "wire the products catalogue to `GET /api/v1/products/` + `GET /api/v1/batches/`". That sounds
narrow. It is not, because the product list has exactly **one** home in the client:

| Fact | Where |
| :--- | :--- |
| `InventoryViewmodel` seeds `_products` from `InventoryMockData.products` | `inventory_viewmodel.dart:17` |
| It **already** calls `assembleCatalogue(products: _products, batches: _batches)` | `inventory_viewmodel.dart:72` |
| `stockRecords` is consumed by 7 files | products, POS, inventory ×4, reports |
| `ProductsViewmodel` reads `_inventory.products` — **decision 11** | `products_viewmodel.dart:45` |

So loading products and batches into `InventoryViewmodel` makes the catalogue live **and** lights up inventory
and POS in the same move, with **no consumer code changes**. The screens would switch from the mock's 10
products / 20 variants to the API's **6 products / 8 variants**.

The question Phase 1 cannot avoid: **is that intended, or does Phase 1 wire only the products screen?**

## Verified contracts (live API, 2026-10-16 — not guessed)

`GET /api/v1/products/` — one call is enough; the serializer nests everything the catalogue needs:

```text
{count: 6, next: null, previous: null, results: [
  {id, category, category_name, brand, brand_name, base_name, description,
   image_url, is_active,
   variants: [{id, product, variant_name, base_uom, base_uom_code,
               min_stock_threshold, max_stock_level, is_active,
               selling_uoms: [{id, variant, uom, uom_code, uom_name,
                               barcode_qr, conversion_factor,
                               default_selling_price}],
               created_at, updated_at}],
   created_at, updated_at}]}
```

`GET /api/v1/batches/` — count 8, read-only, and the only source of stock:

```text
{id, variant, receipt, initial_qty, current_qty, unit_cost_landed,
 markup_percentage, batch_selling_price, expiration_date, created_at}
```

Both match what `Product.fromJson`, `ProductVariant.fromJson` (`json['selling_uoms']`), `VariantUom.fromJson`
and `InventoryBatch.fromJson` already expect, so **no model changes are needed**. `count` is numeric and present
on both, so the strict `parsePaged` contract holds.

## Options

### A. Swap the store, keep the mock as fallback — **chosen**

Add a products/batches service + repository; `InventoryViewmodel.load()` populates `_products` and `_batches`
from it. The catalogue, inventory screens and POS catalogue all go live at once because decision 11 and the
assembler already route through this one store. `InventoryMockData` is **retained** for what the API cannot
serve yet (movements, adjustments, tracking configuration, suppliers).

- **Cost:** the phase boundary blurs — one commit changes what several screens display.
- **Cost:** the write paths (Add / Edit / Archive) still mutate the in-memory store, so a product added in the
  UI survives only until the next load replaces the list. This is *documented*, not hidden.

### B. Swap the store and retire the mock entirely

As A, plus deleting `InventoryMockData`'s product and batch data. Reaches the map's end state sooner, but every
screen whose endpoint is not yet wired (stock movements, adjustments, tracking, suppliers) renders **empty**,
and an empty stock screen reads as "there is no stock" rather than "not wired yet".

### C. Narrow: wire the products screen only, revise decision 11

Leave `InventoryViewmodel` on the mock and give the products screen its own API source. Smallest change, but it
**reintroduces the two-product-list defect that decision 11 exists to remove**, and requires reopening a locked
decision. Rejected.

## Resolution — LOCKED 2026-10-16

**Option A. Swap the store, keep the mock as fallback.**

One store, one load, no consumer rewrites. The blast radius is accepted deliberately: it is the *point* of
decision 11's design that a single store swap lights up every downstream reader, and pretending Phase 1 is
products-only would mean either duplicating the product list (C) or emptying screens mid-migration (B).

Consequent rules for the Phase 1 build:

1. **`parsePaged` is the only envelope unwrapper.** The lost `PosService` (`22c7c26`) hand-rolled
   `data['results']`; that must NOT be lifted, because decision 03 locks the envelope to one place.
2. **The lost `PosService.fetchCatalog()` is a reference, not a drop-in.** It proves the two-call fetch and the
   per-variant stock aggregation work against the real API, but its output is a flat POS DTO
   (not `CatalogueItem`) and it filters to `availableBaseStock > 0` — correct for a till, **wrong for a
   catalogue**, which must show out-of-stock products.
3. **Failures surface, they do not silently empty.** A load error must reach `AsyncView`'s error state, not
   leave the previous list in place or render as "no data".
4. **The mock stays honest.** `InventoryMockData` keeps only what the API does not yet supply, and each retained
   use is commented with the phase that will remove it.

## Accepted cost, stated plainly

The Add / Edit / Archive paths will look like they work but write only to memory. Anyone demoing Phase 1 must
know that. Wiring those writes is a later phase's work, and the interim state is recorded here rather than
discovered later as a bug.
