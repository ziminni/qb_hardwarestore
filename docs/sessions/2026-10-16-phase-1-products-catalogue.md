---
date: 2026-10-16
branch: feature/backend-integration
commits:
  - 6070442  # docs(planning): lock decision 12 - phase 1 loads into the one product store
  - b308717  # feat(products): add ProductsService loading /products/ + /batches/ (phase 1)
  - 5c21329  # feat(products): load the catalogue into the one product store (phase 1)
  - 557dfd3  # feat(products): render the catalogue through AsyncView and load on open (phase 1)
scope: Phase 1 of planning/api-integration/MAP.md — the products catalogue on live API data
repo: qb_pos_inventory_system
skill: wayfinder, executing-plans, verification-before-completion
---

# Phase 1 — the products catalogue on live API data

## Focus

Build Phase 1 of the API-integration map: wire the products catalogue to `GET /api/v1/products/` +
`GET /api/v1/batches/`.

Before writing code, one scope question had to be answered, because **the product list has exactly one home**
(`InventoryViewmodel`) and `ProductsViewmodel` (decision 11) plus `assembleCatalogue` already read from it.
Loading that store therefore lights up the catalogue *and* the inventory and POS screens in one move. The user
chose to accept that blast radius (option A of three), and the choice was recorded as **decision 12** before any
implementation — not left to a commit message.

## What Was Built / Changed

| File | What |
| :--- | :--- |
| `planning/.../decisions/12-phase-1-live-data-home.md` | **Decision 12, LOCKED** — the store swap, what the mock retains, and the accepted cost |
| `flutter/lib/data/services/products_service.dart` | `ProductsService.fetchCatalogue()` → both endpoints via `ApiClient.getList<T>`, so `parsePaged` unwraps each envelope (decision 03). `ProductsSnapshot {products, batches}`. `DioException` → `ProductsServiceException` |
| `flutter/lib/data/repositories/products_repository.dart` | Pass-through, keeping `View → VM → Repo → Service → ApiClient` |
| `flutter/lib/features/inventory/viewmodels/inventory_viewmodel.dart` | `load()`, `isLoading`, `loadError`, `hasLoaded`; injected `ProductsRepository` defaulting to the real one, so all 27 existing `InventoryViewmodel()` sites keep working |
| `flutter/lib/features/products/views/products_page.dart` | `StatelessWidget` → `StatefulWidget`; loads on open; the four states render through `AsyncView` |

Three test files, 15 tests: `products_service_test.dart` (4), `inventory_viewmodel_load_test.dart` (8),
`products_page_load_test.dart` (3). Suite **131 → 146**.

Contracts were probed against the **live API** before coding: `/products/` (count 6) nests
`variants` → `selling_uoms` → `default_selling_price`; `/batches/` (count 8) carries `current_qty`. All four
`fromJson` factories already matched, so **no model file was touched** — checked with
`git diff --name-only … | grep data/models` → none.

One test exists purely as a decision-03 anti-regression: a body with no `results` list must **throw**, because
the lost `PosService` hand-rolled `data['results']` and that turns a contract break into a silent "no products".

## Mistakes & Gotchas (Do Not Repeat)

- **I judged the lost work by its filename and got it wrong.** I dismissed `22c7c26` as "POS code, nothing
  salvageable for Phase 1" because the file is `pos_service.dart`. Reading it showed `fetchCatalog()` makes
  *exactly* Phase 1's two calls. It is a **reference, not a drop-in** — but I had already stated a conclusion I
  had not checked. Read the code, not the path.

- **The mock has 12 products, 20 variants, 21 batches — not the 10/20/20 I asserted from memory.** My test
  failed with "has length of <12>". The wrong number was mine. Assertions now compare a **captured baseline** or
  use identity (`'Circuit Breaker'` is the API's product, so its *absence* proves the mock is in play) instead of
  hard-coding a size. Hard-coded counts rot silently.

- **Third silent grep under-match of the session.** Verifying the RED log I grepped `isn't defined` and got 0 —
  the compiler says **"No named parameter with the name 'products'"**. The RED was real (12 such errors); my
  pattern was wrong. Earlier cases: `[a-z-]*` could not match `phase-0-complete`, and a `LOCKED` grep mis-counted
  decision status. **In this repo an empty grep result is suspect until the pattern is proven against a
  known-present string.**

- **My own wrong working directory produced a false "files missing".** A final check ran `ls
  lib/data/...` from the repo root instead of `flutter/`, reported MISSING, and I nearly carried it into a
  report. It was a path bug. Re-run correctly: 1755 B / 2135 B / 3262 B, all present.

- **A full-screen widget test needs `AuthViewmodel`.** `InventorySkeletonLayout` is the shared shell and reads
  it; `ProductsPage` alone threw `ProviderNotFoundException`. Any test rendering a whole screen must provide the
  shell's dependencies, not just the screen's own viewmodels.

- **PRE-EXISTING DEFECT, found not fixed: the products toolbar overflows.** `A RenderFlex overflowed by 9.7
  pixels on the right` at both 800×600 and 1600×1400, in `products_toolbar.dart:113` and
  `products_catalog_overview.dart:156` — neither touched by Phase 1. It renders as a visible overflow stripe at
  that window width. The page test runs at 2560×1600 so it can assert wiring without tripping an unrelated
  layout bug. Fixing it is UI work outside Phase 1's scope.

- **The page deferred its load to `addPostFrameCallback`, and that is load-bearing.** `load()` calls
  `notifyListeners()` synchronously; doing that from `initState` means marking an element dirty mid-build.
  Because the deferral leaves one frame where the store still holds **mock** data, the view passes
  `isLoading: isLoading || !hasLoaded` — otherwise 12 mock products visibly flash before the API's 6 arrive.

## Decisions

- **Decision 12 — Phase 1 loads into the one product store; the mock is retained as fallback.** Chosen over
  retiring the mock outright (screens whose endpoints are unwired would render empty and read as "there is no
  stock") and over a products-screen-only API source (which would reintroduce the two-product-list defect
  decision 11 exists to remove). Consequence recorded as an **accepted cost: the Add / Edit / Archive paths stay
  memory-only until their phase**, so a product added on screen survives only until the next load.
- **A failed load keeps the catalogue.** It surfaces `loadError` and leaves the list exactly as it was. Emptying
  it would render as a legitimate "no products" the user cannot act on; half-filling it would invent a
  catalogue. Asserted against a captured baseline, because the property is "unchanged", not "a given size".
- **`hasLoaded` distinguishes "not fetched yet" from "fetched and empty"**, and a *failed* attempt still counts,
  so a failure shows the retryable error instead of spinning forever.

## Wins & Next Step

Verified fresh at `557dfd3`, all in one pass: `flutter analyze` → **"No issues found!"**; `flutter test` →
**146 passing, exit 0**; tree **clean**; **87** commits ahead of `origin/master`; live API re-probed
(`/products/` count 6, `/batches/` count 8).

**Step 4's test was written AFTER the wiring — a real TDD deviation, recorded rather than hidden.** It was
later closed properly with a red-green check: reverting `products_page.dart` to its pre-wiring version makes the
test **fail (exit 1)**, restoring makes it **pass (3/3)**. So it is a genuine regression test, but the
implementation was not driven red-first.

**Honest limitation: `flutter run` was never executed.** The *contract* is verified by probing the live server,
and the *wiring* by widget tests against a fake adapter — but the running app has not been exercised against the
real backend.

**Next step: Phase 2 — inventory (stock list, low stock, movements).** It needs no new decisions; the
batch-vs-adjustment distinction was settled by Phase 0 rulings R12–R14. Because Phase 1 made
`InventoryViewmodel` API-backed, the inventory screens are **already reading live products and batches** — Phase
2's work is their remaining endpoints (movements, adjustments, alerts, tracking) plus removing the corresponding
mock. Phases 3, 5 and 6 stay gated by decisions 06, 09 and 05.

Carried forward unfixed: the toolbar overflow above; the backend bug in
`apps/inventory/services.py::apply_stock_adjustment` (a positive adjustment is silently discarded when no batch
has `current_qty > 0`); and the seed-data FIFO gap (8/8 variants carry one batch).
