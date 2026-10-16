---
date: 2026-10-16
branch: feature/backend-integration
commits: [8176b71, 9266ab4, dcb9ae1, 0b8d522, 47ce489, 0fe7f6e, 27f687f, 5e4d9ca, 113f7a3, 67aed45, eebe001, 388109d, 4b5aa16, c6cabe9, cbef80c, 42e2a23, fb1a6bd, 115dcd7, 68c5750, 6b3852b, 327ce9e, 84469ba, 0bfec92, db4ad8f, be1fdee, 413a17f, 007edec]
scope: Flutter client only — models, services, viewmodels, widgets and tests. No backend change.
repo: qb_pos_inventory_system
skill: executing-plans (inline), then a fresh-context review
---

# Session — The Staged Model Swap, Finished

## Focus

Execute the Phase 0/1 plan inline under the `executing-plans` skill: make the Flutter client mirror the
backend's real shape by removing the invented `ProductVariant` fields. The previous session had stopped at
ruling R9 with two unanswered product questions.

## What Was Built / Changed

**27 commits. The four-step staged swap (ruling R8) is complete, plus the assembler and the location store.**

| Piece | What landed |
| :--- | :--- |
| **Test harness** | `flutter test` could not run *at all* before this work — one uncompilable generated file failed the whole suite. Replaced with a launch smoke test. TDD was impossible in this repo until then. |
| **Models** | `VariantUom`, `InventoryBatch`, strict DRF readers (`json_field.dart`) that throw on missing required fields instead of defaulting to 0. |
| **Step 1** | `ProductVariant` gained `productId`, `baseUomId`, `minStockThreshold`, `maxStockLevel`, `sellingUoms` — **required**, never defaulted. Cost: 21 construction sites had to be fixed. |
| **Step 2** | `CatalogueItem` + `assembleCatalogue({products, batches})` — price from the selling unit, stock summed from batches. |
| **Step 3** | Mock data materialised (20 lots, 20 selling units); variant 1's 130 split into **two lots of 80 + 50** so FIFO can cross a batch boundary; `InventoryViewmodel` became batch-backed (`batchesFor`, `stockOnHandFor`, `latestBatchFor`, `catalogue`, `barcodeFor`, `priceFor`, `costFor`, `statusForVariant`); **all 16 readers migrated**; the products form now returns `ProductFormResult{product, openingStock}`. |
| **Step 4** | Deleted `sku`, `qrIdentifier`, `costPrice`, `sellingPrice`, `currentStock`, `storageLocation`, the `reorderLevel` getter, `_syncLegacyStock()` and the transitional `statusFor(ProductVariant)` overload. 120 legacy constructor args removed from the mock data. |
| **Location hints** | `LocationHintStore` over `shared_preferences`, keyed by variant id, owned by the viewmodel, loaded once in `main.dart`. Explicitly **not** API data. |
| **Review fixes** | Negative corrections clamped; `mergePrimarySellingUom` preserves extra selling units. |

`ProductVariant` now carries exactly: `id`, `productId`, `baseUomId`, `minStockThreshold`, `maxStockLevel`,
`sellingUoms`, `variantName`, `baseUomCode`, `isActive`, plus the derived `barcode` getter.

Tests went **0 runnable → 30 → 65**. `flutter analyze` clean at every commit.

## Mistakes & Gotchas (Do Not Repeat)

### 1. `grep '\.<field>'` matches the REPLACEMENT, not just the original

Counting "legacy references remaining" by field name is wrong twice over:

- `grep '\.currentStock'` also matched `widget.currentStock` — the parameter I had *just introduced*. A finished
  file read as 5 refs remaining.
- It also matches **same-named fields on unrelated classes.** `ProductTrackingConfiguration` has its own
  `storageLocation`/`costPrice`/`sellingPrice`; `Supplier.sku` and `SalesLine.sku` drive the sales and reports
  screens. Migrating by field name alone would have corrupted the product-tracking and sales features.

**Rule: count legacy references by the receiver — `variant\.<field>` — never by field name.**

### 2. A check that reports "none" may have examined nothing

My first equivalence script (proving the three substitutions value-preserving) matched **0 of 20** variants and
printed `MISMATCHES: none` — indistinguishable from a real pass. Caught only because `variants parsed: 0` was
printed beside it.

**Rule: every check prints how many things it examined, and asserts that number.** The rerun asserts
`len(v) == 20`.

Same class of error, opposite direction: a regex `\..sku` needs five characters, so it matched nothing and
reported `sku` as *unused* while it was in 17 files.

### 3. Multi-edit calls can PART-APPLY, and the summary hides it

Twice, a call applied some edits and dropped one — once because two edits for *different files* went under one
path, once because the `oldText` had drifted. Both times the result was a real compile error reported as
"PARTIAL APPLY" rather than a clean failure.

**Rule: after any PARTIAL APPLY, read the reported diagnostics and fix before committing. One file per edit call
when edits touch different files. Build `oldText` from a fresh read, not an earlier grep.**

### 4. Deleting a widget from a nested collection can eat its closing bracket

Removing the SKU field consumed the `],` that closed a `...[spread`, producing `Expected to find ']'` at **line
743** — 400 lines from the edit. The replacement was also at the wrong indent, because the original field sat at
a shallower level than I assumed.

**Rule: when removing an item from a spread or list, re-read the region and check the closing bracket.**

### 5. An async side effect in a constructor breaks every test that constructs the class

`unawaited(loadLocationHints())` in the `InventoryViewmodel` constructor failed **18 unrelated tests** with
"Binding has not yet been initialized". The tempting fix was adding `TestWidgetsFlutterBinding.ensureInitialized()`
to the test — that patches the symptom. The real defect was that *constructing a viewmodel* reached platform
storage.

**Rule: constructors take dependencies, they do not perform I/O. Do the I/O in an explicit `load()` the caller
awaits.**

### 6. `dart format` rewrites files AFTER a commit — five times this session

A file is reported "auto-fixed", then shows as modified. Once it collapsed `group(...) {` and `test(...)` onto
one line — a genuine formatting defect that `dart analyze` did not flag.

**Rule: commit formatting churn separately (`style:` commits) so it never rides along with a feature commit, and
re-read any file reported as auto-fixed before further edits.**

### 7. A persistent stale-diagnostic cache will lie about freshly-written files

The harness repeatedly reported `Target of URI doesn't exist` and `The getter 'barcode' isn't defined` long after
those existed. Settled **four independent ways**: `sed` of the definition, `dart analyze <that exact file>`,
a fresh `lens_diagnostics source=lsp mode=full` probe (0 diagnostics), and the suite. Never "fix" a stale
finding — fixing a non-issue means editing working code to satisfy a cache.

## Decisions

- **Decision 10 — `sku` does not exist in the backend.** Verified three ways (models, serializers, live API): the
  only sku-like column in the whole schema is `VariantUom.barcode_qr` (`apps/inventory/models.py:128`). The
  `CEM-HOL-40`-style values were **invented by the mock data**. The SKU column became a **Barcode** column;
  storage location became a **persisted client-local hint**, explicitly not API data.
- **R12 — the mock mirrors the backend's implemented behaviour**, not invented semantics:
  `allocate_fifo` deducts oldest-batch-first; `apply_stock_adjustment` sends additions to the **newest** batch.
- **R13 — FIFO orders by `receiptId`**, because all 20 mock batches were materialised with `createdAt: null`.
- **R14 — FIFO crossing a batch boundary was untestable**: every variant has exactly one batch, in the mock *and*
  in `seed_demo` (8/8). Fixed by splitting variant 1's lot. **The same gap still exists in the live seed data.**
- **R16 — the constructor side-effect fix** (see gotcha 5).
- **R23 — kept `copyWith(currentStock:)` until step 4**, because the transitional mirror needed it.
- **R24 — deliberately diverged from the backend on one path, and recorded it.** A positive adjustment on a
  variant with no `current_qty > 0` batch is **silently discarded** by `apply_stock_adjustment`. Mirroring a
  silent data loss would be a visible defect in the demo, so the count is honoured at zero cost.
  **Raised as a probable BACKEND BUG — see below.**
- **Decision to keep the plan workspace** rather than delete it after the review: `MAP.md` points at
  `.superpowers/sdd/MAP/progress.md` ruling R7, and the plan is not finished (Phases 1–6 remain).

## Wins & Next Step

**Verified:** `flutter analyze` → `No issues found!`; `flutter test` → **65/65 pass**; tree clean; branch
`feature/backend-integration` **66 commits ahead** of `origin/master`, unpushed. The staged model swap is done
and reviewed by a fresh-context subagent (no Critical findings).

### ⚠️ Probable BACKEND bug found during the final review — act on this

`backend_django/apps/inventory/services.py`, `apply_stock_adjustment`:

```python
batch = InventoryBatch.objects.filter(variant=variant, current_qty__gt=0)...
if batch: ...
```

If every batch for a variant is at zero, `batch` is `None` and **a positive stock adjustment is silently
discarded** — the user's typed correction vanishes with no error. A count correction on a depleted item is
normal. Out of scope for this client-only map; needs a backend issue.

### Deferred minors (the review's, unfixed by design — your call)

- `latestBatchFor` is the absolute newest batch; the backend's addition target is the newest with
  `current_qty > 0`, so `costFor` can attribute cost to an empty lot.
- Low-stock boundary off by equality: client `stock <= threshold`, backend `total < threshold`.
- Two independent id authorities — `ProductsViewmodel.addProduct` and `InventoryViewmodel.addProduct` each
  compute `max(id)+1` over their own copy.
- `pos_transaction_viewmodel.complete()` re-validates nothing before deducting; safe only because the payment
  dialog validates first.
- `LocationHintStore.hintFor` has no production caller.
- New-product variants use a microsecond timestamp as an id; the constructed `VariantUom` carries `variantId: 0`.
- **The location hint is display-only.** Decision 10 calls for it to be *editable*; the edit affordance is unbuilt.

### Next step

**Phase 1 — wire the products catalogue to `GET /api/v1/products/` + `GET /api/v1/batches/`.** Everything it
needs now exists and is locked: `ApiClient.getList<T>` returning `Paged<T>`, `core/widgets/async_view.dart`
(decision 07), and `assembleCatalogue`. A salvageable earlier attempt sits in commit `22c7c26`
(`planning/02-lost-work-recovery.md`). Note `ProductsViewmodel` and `PosTransactionViewmodel` are still **not
registered** in `main.dart`.
