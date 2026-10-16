---
date: 2026-10-16
branch: feature/backend-integration
commits: [6e6db8b]
scope: planning only — no application source modified
repo: qb_pos_inventory_system
skill: wayfinder (Map Mode, Phase 0 resolution)
---

# Session — Phase 0 Decisions Locked (Integration Map)

## Focus

Resolve the Phase 0 frontier of `planning/api-integration/MAP.md` — starting with
[Product & Variant Client Model Shape](../../planning/api-integration/decisions/02-product-variant-client-model.md),
then continuing through pagination, async states and role routing — so Phase 0's *decisions* no longer block
the coding work. (Phase 0's *code* is a separate, unfinished matter — see the correction under "Wins & Next
Step".)

Research surfaced **two decisions the map did not have**, both now recorded: pricing, and requisition UI
ownership.

## What Was Built / Changed

| Path | Change |
| :--- | :--- |
| `decisions/02-product-variant-client-model.md` | **LOCKED** — mirror the API's four entities + a computed `CatalogueItem`. |
| `decisions/03-pagination-envelope-strategy.md` | **LOCKED** — one `ApiClient.getList<T>` returning `Paged<T>`. |
| `decisions/07-loading-error-empty-convention.md` | **LOCKED** — `auth_viewmodel` field convention + shared `AsyncView`. |
| `decisions/04-role-dashboard-routing.md` | **LOCKED** — a foreman is a CPMS-side identity, not a POS user. |
| `decisions/08-pricing-rule.md` | **NEW, LOCKED** — `VariantUom.default_selling_price` is what is charged. |
| `decisions/09-requisition-ui-ownership.md` | **NEW, OPEN** — POS should build approve + release, not creation. Phase 5. |
| `planning/api-integration/MAP.md` | Phase 0 hand-off table; 6 locked · 3 open. |
| `README.md` | `foreman` row corrected — no POS UI role, by design. |
| `AGENTS.md` | Next step repointed from "resolve decision 02" to "build Phase 0, then Phase 1". |

Commit: `6e6db8b`. The map itself was opened the previous session (`664f109`, `722279f`).

## Mistakes & Gotchas (Do Not Repeat)

### The "imagined API" claim was wrong, and it was mine

The previous session recorded that `product.dart` was "written against an imagined API". The live API proves
**7 of its 9 suspect fields are real** — they simply belong to *other entities*. The client had flattened a
3-level hierarchy (`Product` → `ProductVariant` → `VariantUom`) **plus** a separate stock ledger
(`InventoryBatch`) into one class:

| Client field | Actually lives on |
| :--- | :--- |
| `reorderLevel` | `ProductVariant.min_stock_threshold` |
| `qrIdentifier` | `VariantUom.barcode_qr` (empty `''` in seed data) |
| `sellingPrice` | `VariantUom.default_selling_price` |
| `costPrice` | `InventoryBatch.unit_cost_landed` |
| `currentStock` | `InventoryBatch.current_qty` |
| `sku`, `storageLocation` | nothing anywhere — the only genuinely invented fields |

Before calling a client field invented, check whether it exists on a *sibling* entity. `Product.fromJson` was
correct all along, including nested `variants`.

### `?? 0` fallbacks are what hid it

The API sends no price or stock on `/variants/`, so `fromJson`'s `?? 0` defaults turned every variant into
**₱0.00 with zero stock** — plausible-looking and wrong, rather than a crash. Locked rule: rewritten `fromJson`
implementations must not swallow missing required fields.

### Probe the running API, not just the serializers

Reading `serializers.py` gave the field list but would have missed the load-bearing fact: **neither
`/products/` nor `/variants/` exposes stock, cost or price — they live only on `/api/v1/batches/`**. That is
what makes a client-side join unavoidable, and therefore what justifies the catalogue assembler. Live shapes
also revealed the real nesting (`Product.variants[]`, `ProductVariant.selling_uoms[]`).

### Two price fields disagree by 75% in seed data

`VariantUom.default_selling_price` = ₱315.00 vs `InventoryBatch.batch_selling_price` = ₱180.00 for the same
variant. A silent modelling assumption would have picked one; it needed a business decision. Note
`batch_selling_price` equals `unit_cost_landed` (₱180.00), i.e. zero markup — so it reads as a cost passthrough.

### Dates were written without checking the clock

Six decision files were stamped `LOCKED 2026-10-15` when the work happened **2026-10-16** (evidence: file
mtimes 08:46-08:59, commit at 09:00). I assumed the date instead of reading it. Caught during save-progress
evidence gathering, and corrected in 7 files. **Read the clock; do not infer the date from the session's
start.**

### Locking a decision means updating three places, and I updated two

After locking, decisions 01 and 03 still read `Status: OPEN` in their headers — I had replaced the Resolution
body but never the header. A locked decision needs: header status, resolution body, **and** the map's
locked/open lists. Now verified programmatically (9/9 headers agree with the map).

### My verification script reported six false failures

The header-vs-map check used `dict()` over `re.findall` (keyed by *title*) and then tested *filenames* against
it, so every locked file appeared mismatched. When a check claims everything is broken, suspect the check
first. Corrected with `set(...)` over the filename capture group.

### Smaller traps

- `ask_user_question` labels are hard-limited to **60 characters**; a 61-char label is rejected outright.
- `lens_diagnostics source=lsp` needs explicit **file** paths — a directory errors with `not a file`.
- Never run a verification command in the same tool block as the edit it checks: they execute concurrently and
  the check reads pre-edit state.
- An emoji-based row counter also matched a *different* table using the same emoji; scope the parse to the
  intended table.

## Decisions

| Decision | Resolution |
| :--- | :--- |
| **Product & Variant model** | Mirror the API's four entities (`Product`, `ProductVariant`, `VariantUom`, `InventoryBatch`) plus one computed `CatalogueItem { product, variant, uom, price, stockOnHand }`. Delete `sku` and `storageLocation`. |
| **Pagination** | Single `ApiClient.getList<T>` returning `Paged<T>`, unwrapping `.results` in one place. No seeded list exceeds one page (max 8 vs `PAGE_SIZE = 50`), so paging is deferred. |
| **Async states** | Viewmodels follow the `auth_viewmodel` public-field convention; one shared `core/widgets/async_view.dart` owns loading/error/empty rendering. No base class. |
| **Role routing** | A Site Foreman is a **CPMS-side identity**, not a POS user. `site_foreman` gets no POS dashboard; unmapped and role-less accounts route to an explicit unsupported-role screen instead of looping to `/login`. |
| **Pricing** *(new)* | `VariantUom.default_selling_price` is charged. `batch_selling_price` is display-only. Cost shows the latest batch's `unit_cost_landed`, labelled as such. |
| **Requisition UI ownership** *(new, open)* | Recommended: POS builds approve + release only; creation and submission belong to CPMS. Phase 5. |

## Wins & Next Step

**Phase 0's DECISIONS are complete** — 6 locked, 3 open, and nothing blocks the Phase 0 *code*.

> ⚠️ **Corrected 2026-10-16.** This line originally read "**Phase 0 is complete**", which conflated *locked
decisions* with *delivered code* and was false. Phase 0's code is **2 of 7 rows done** (Models and Assembler).
The authority for that status is the **"Phase 0 — status"** table in
`planning/api-integration/MAP.md`, not this note.

Verified: 21 doc files with 0 broken links · all 9 decision headers agree with the map's locked/open lists ·
6 locked · 3 open · no orphan or missing decision files · 7 changed files with 0 diagnostics · working tree
clean apart from the deliberately-untracked `flutter/test/`. Branch is 39 commits ahead of `origin/master`,
unpushed.

**Next step:** build the Phase 0 deliverables listed in the hand-off table in
`planning/api-integration/MAP.md` — the four models, `ApiClient.getList<T>`, `core/widgets/async_view.dart`,
the catalogue assembler, the routing fix, and registering the two unregistered viewmodels — then start
**Phase 1**: wire the products catalogue to `GET /api/v1/products/` + `GET /api/v1/batches/`.

Two pre-existing bugs are in that brief and should be fixed while there: `products_page.dart` watches
`InventoryViewmodel` instead of its own viewmodel, and `ProductsViewmodel` / `PosTransactionViewmodel` are
absent from `main.dart`'s provider list.
