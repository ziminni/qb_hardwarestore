---
date: 2026-10-16
branch: feature/backend-integration
commits: [8176b71, 9266ab4, dcb9ae1, 0b8d522, 47ce489, 0fe7f6e, 27f687f, 5e4d9ca, 113f7a3, 67aed45, eebe001]
scope: Flutter client only — models, services, mock data and tests. No backend change.
repo: qb_pos_inventory_system
skill: executing-plans (Phase 0), then wayfinder (unblocking R9)
---

# Session — Staged Model Swap: Blockers Resolved and the Location Store

## Focus

Resume the inline Phase 0 execution, then find why it had stopped midway and unblock it.
The build stopped on ruling **R9**: step 3 of the staged `ProductVariant` swap needed two product
decisions that the spec did not cover, and the assistant refused to pick a UI behaviour silently.

## What Was Built / Changed

Eleven commits. The staged swap (ruling R8) went from "not started" to "steps 1 and 2 complete, step 3
unblocked".

| Commit | What |
| :--- | :--- |
| `8176b71` | `.gitignore` gains `.superpowers/` — the executing-plans scratch workspace |
| `9266ab4` | Replaced the broken counter template in `flutter/test/widget_test.dart` with a launch smoke test. **This was the blocker that made TDD impossible**: one uncompilable file failed the whole suite |
| `dcb9ae1` | API-faithful `VariantUom`, `InventoryBatch` and the strict `json_field.dart` readers, with wire tests |
| `0b8d522` | Recorded the **measured** migration blast radius in the plan |
| `47ce489` | **Staged swap step 1** — `ProductVariant` gains `productId`, `baseUomId`, `minStockThreshold`, `maxStockLevel` (all **required**) plus `sellingUoms` |
| `0fe7f6e` | **Staged swap step 2** — `CatalogueItem` + `assembleCatalogue` |
| `27f687f` | `dart format` fixup |
| `5e4d9ca` | **Mock data materialised** — 20 variants gained real `sellingUoms`, and the mock stock numbers became a `static const batches` list of 20 `InventoryBatch` rows |
| `113f7a3` | **Decision 10 locked** + `LocationHintStore` + `shared_preferences ^2.5.6` |
| `67aed45` | macOS generated registrant registers the `shared_preferences` plugin |
| `eebe001` | `dart format` fixup |

### Decision 10 — the two R9 blockers

**Blocker 1 — `sku` and `storageLocation` have no backend counterpart, but are visible columns.**
`sku` appears in 4 tables, `storageLocation` in 2 tables *plus the stock page's location filter*, with 20
hand-written mock values (`Rack A-01`, `Yard E-02`). Resolved:

- **The SKU column becomes a Barcode column** fed by `VariantUom.barcodeQr` — the only identifier in the
  schema, honestly labelled. It renders blank today because `barcode_qr` is `''` in every seeded row.
- **Storage location becomes a persisted client-local hint** (`shared_preferences`, keyed by variant id,
  one JSON blob). Explicitly **not** API data; the UI must not present it as if the server sent it.

**Blocker 2 — add-product had to create stock somewhere real.** The form collected quantity and cost onto
`variant.currentStock`, the field step 4 deletes. Resolved: it now creates **one opening `InventoryBatch`
per variant** (`initialQty`/`currentQty` from the form, `unitCostLanded` from the cost field), so new stock
is immediately sellable and counts toward low-stock like seeded stock.

## Mistakes & Gotchas (Do Not Repeat)

### 1. A stale lint cache claimed freshly-written files did not exist

After writing `location_hint_store.dart`, the harness reported 12 blockers — `Target of URI doesn't exist`,
`Method not found: 'LocationHintStore'` — and repeated the same for the catalogue files after *those* had
been written. **The advisory was stale, and "fixing" it would have meant rewriting working files.**

Verified three ways instead of acting:

```text
ls            → location_hint_store.dart, 3240 bytes, on disk
dart analyze  → "No issues found!"
fresh LSP     → lens_diagnostics source=lsp mode=full on the exact paths → 0 diagnostics
```

The same applied to the catalogue advisory, which was self-labelled `[stale — re-run to confirm]`.
**Rule: when a check claims everything is broken, suspect the check first** — and re-probe before editing.

### 2. The `write` tool's `dart format` rewrites files *after* a commit

Hit **twice**: once on the catalogue files (`27f687f`) and once on the location store (`eebe001`). A file is
reported "auto-fixed", then shows as modified once you look at `git status`. Any file reported as auto-fixed
**must be re-read before further edits**, and the reformat committed separately so it does not pollute the
next feature commit.

### 3. `edit` refuses a file not read in the same conversation

Returns `RETRYABLE - Edit without read ... Read it first, then retry`. Reading a file's contents in an
earlier summary or tool result does not satisfy it.

### 4. `reorderLevel` is two different fields

`flutter/lib/features/products/widgets/products_form_dialog.dart` contains two occurrences.
`ProductVariant.reorderLevel` became a **derived getter alias** for `minStockThreshold` (one source of truth
rather than two stored fields). The other belongs to `ProductTrackingConfiguration`, a **different class**,
and must not be renamed. `product_tracking.dart` also has its own `storageLocation` — the product-tracking
feature is unaffected by this swap.

### 5. Required, not defaulted

The API-faithful fields are **required**, never defaulted to `0`. This is what made step 1 non-inert: the
`0`-default version was written first, rejected as the forbidden silent-zero pattern, and replaced — which
forced 21 construction sites to be fixed. See decision `02`.

## Decisions

- **`sku` does not exist in the backend — verified three ways.** Model fields (`Product`:
  `category, brand, base_name, description, image_url, is_active`; `ProductVariant`: `product,
  variant_name, base_uom, min_stock_threshold, max_stock_level, is_active`), the serializers, and the live
  API all agree. The only sku-like column in the entire schema is `VariantUom.barcode_qr`
  (`apps/inventory/models.py:128`). **The `CEM-HOL-40`-style SKUs were invented by `inventory_mock_data.dart`**
  and were never in any database. The client had been asserting an identifier that no system owned.
- **Decision 10 locked** — `planning/api-integration/decisions/10-stock-identifier-and-location-hint.md`.
- **Ruling R10** — R9's two blockers resolved as above. *Cost if wrong:* `barcode_qr` is empty until real
  barcodes are recorded, and the hint store is a second source of truth outside the API.
- **Ruling R11** — stale-cache findings verified rather than "fixed". *Cost if wrong:* had the cache been
  right, a real compile error would still stand — which is exactly why the authoritative check was run.
- **Locking a decision means three edits in sync**: the decision file's header `Status` line, its
  `Resolution` body, and `MAP.md`'s locked list. A lock recorded only in the body leaves the header reading
  `OPEN` and breaks the map's counts.

## Wins & Next Step

**Verified:** `flutter analyze` → `No issues found!`; `flutter test` → **30/30 pass** (up from 0 runnable at
session start); tree clean; branch `feature/backend-integration` **51 commits ahead** of `origin/master`,
unpushed. The map now reads **7 locked · 3 open**.

The Floor works for the first time in this repo: `flutter test` could not run *at all* before `9266ab4`.

**Next step:** finish **staged-swap step 3** — migrate the 13 reader-only files onto `CatalogueItem`, relaying
the Barcode column into the 4 tables and wiring `LocationHintStore` into the 3 location sites
(`inventory_stock_table`, `inventory_low_stock_table`, `inventory_stock_page`'s filter). The owning crux is
`InventoryViewmodel`, which is a **mutable mock store** — `adjustStock`/`sellStock` mutate
`variant.currentStock`, so stock mutation must move onto `_batches`. Then **step 4** deletes `sku`,
`storageLocation`, `costPrice`, `sellingPrice`, `currentStock` and the `reorderLevel` getter.

Per-file plan and rulings live in `.superpowers/sdd/MAP/progress.md` (gitignored — the durable copies are
this note, `MAP.md` and the decisions).

**Next session opening questions:**

1. **Step 3 is payment-related** — confirming `adjustStock`/`sellStock` become batch-scoped is a product
   call, not a rename.
2. `flutter/macos/`, `flutter/linux/` and other platform dirs: is `flutter/linux/` meant to stay untracked?
