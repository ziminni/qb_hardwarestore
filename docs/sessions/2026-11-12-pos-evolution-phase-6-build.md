# POS evolution Phase 6 — build, gates and review handoff

## Status

**Phase 6 🟡 In Progress — build, review, gates and isolated live QA complete; OWNER CLOSURE STILL PENDING.** Branch `feat/pos-evolution-phase-6`, from planning `80d7174` (includes Phase 5 `864a667`). All 18 items of [decision 22](../../planning/pos-evolution/decisions/22-cleanup-list.md) are implemented and individually reviewed, and the independent whole-change review is **APPROVED with no Critical or Important finding**. QA (`temp/p6/qa/report.md`) found **no confirmed defect in the exercised acceptance flows**, but the phase is **not owner-closed and not done**. No commit, push, dev mutation, deployment or Phase 7 is authorized. Current task/evidence status belongs in [the Phase 6 plan](../../planning/pos-evolution/phase-6-plan.md); this note records the checkpoint.

## Implemented scope (cleanup only — no new feature)

- **Guarded sales-order and quotation writes (B1, item 16).** An order is create-only: `PUT`/`PATCH`/`DELETE` on the detail are **405 for every role, Admin included**, so an order with a `Delivery` can no longer answer a `ProtectedError` 500; the order, its lines, its optional delivery and its one `CREATE` audit row commit or roll back together. A quotation's `status` is read-only, editing/erasing one is Store Manager/Admin only and carries its `UPDATE`/`DELETE` audit row in the same transaction, and a nested `items` write on update is **400** instead of DRF's `AssertionError` 500. A PATCH of read-only fields only saves nothing and audits nothing.
- **Archived catalogue rows refused (B3, item 14).** `refuse_inactive_selling_unit` (`common/exceptions.py`) → **400 `INACTIVE_SELLING_UNIT`** when the unit's variant or its product is archived, wired into both item serializers before the first write: no document, line, delivery or audit row, and **no consumed document number**.
- **Race-safe document numbers (B4, item 19).** `generate_document_number` reserves from `DocumentCounter` under `select_for_update` (the TRX/OR pattern) seeded from `highest_existing_sequence`; callers unchanged, **no new table or migration**; a rolled-back caller leaves a gap, never a duplicate.
- **Money and state Minors (B2, B5).** Supplier-bill discount capped at the PO header discount (over-receipt can never over-allocate) with the docstring example corrected; `money_round` made public for requisitions; a settings PATCH catches `ValidationError` only so unexpected errors are honest 500s; a no-change settings PATCH saves nothing and writes no audit row.
- **Seed repair (B6, item 17).** Variants keyed by `(product, variant_name)`, packaging guard checks the complete shape and creates only missing parts, stock gate is "variant has any batch" — re-seeding a half-built fixture no longer collides or duplicates.
- **Flutter Minors (F1, F2).** Till low-stock badge from the product's own server threshold (not a hardcoded 10); receipt prints the server's `change_given`; one shared money validator; money errors wrap at 760/1.3 instead of clipping; "New sales order" hidden on a load error; null VAT reads "Not recorded"; legacy product with no location id can finally take one; double-tapped "add location" no longer claims success.

## Verified gates (automation, this phase)

Run under controller ownership on the isolated stack; logs are **local and gitignored** under `temp/p6/full/`:

| Gate | Result | Evidence |
| --- | --- | --- |
| Django full suite | **1064 tests OK** | `temp/p6/full/backend.log` |
| `manage.py check` | clean (`CHECKEXIT=0`) | same log |
| `makemigrations --check --dry-run` | **No changes detected** (`MIGEXIT=0`) — no migration added | same log |
| `flutter analyze` | **No issues found!** | `temp/p6/full/analyze.log` |
| Flutter ordinary suite | **2008 passed / 241 skipped** | `temp/p6/full/flutter.log` |
| Goldens (`RUN_GOLDENS=true`) | **241 passed** | `temp/p6/full/golden-final.log` |
| Whole-change review | **APPROVED**, no blockers | `temp/p6/review/report.md` |

**Exactly one golden changed:** `.superpowers/sdd/ui-refresh/goldens/m3-orders-error-760.png` (`3a063986…` → `7547a756…`). F1 item 11 hides the "New sales order" button while the page shows a load error, so the button left the frame and everything below shifted up ≈52 px (20.47 % diff, 140 036 px). The controller inspected before/after, reproduced the new render byte-identically on a second run, and confirmed the other **240** captures are byte-identical (`temp/p6/goldens-before/`, `temp/p6/goldens-before.md5`, `temp/p6/goldens-after.md5`, `temp/p6/golden-review/report.md`). Masters live only on this machine (`.superpowers/` is gitignored).

## Isolated live QA — complete, owner closure still open

The lane ran on `buildpro_p1d_qa_{db,backend,web}` on `172.20.0.*` (API `:8001`, web `:8091`); dev containers were observed stopped and were never started or written. `temp/p6/qa/report.md` is now complete: **no confirmed defect in the exercised flows**. API: order `PUT`/`PATCH`/`DELETE` **405**, quotation cashier write **403**, archived product/variant refusal **400 `INACTIVE_SELLING_UNIT` with zero writes** (document/line/delivery/audit/counter snapshots equal before/after), concurrent order creates **201/201 with distinct numbers**, no-change settings PATCH **200 with no audit row or `updated_at` change**. Clean host-only browser rerun (fresh sessions, no shim/override, no cached worker): manager + cashier login on `/api/v1/…` with no double-prefix, offline order load shows `Retry` and no New-order button with online retry restoring both, 760 till delivery-fee error wraps, and low-stock thresholds pass for a base unit and a package unit (restored to 20.00). **Not verified:** zero-stock till badge, legacy null location / null PO-VAT rows (none exist), fresh completion-dialog Change display on the clean build (the ₱240 Change UI was verified only in the historical shim run; the clean run reads `change_given:"240.00"` from the API while the detail shows no Change line), and the clean narrow order-fee error (historical shim pass only). **Controller-observed Low cosmetic**, outside the targeted money-field fix and awaiting the owner's defer/fix decision: `temp/p6/qa/screenshots/clean-host/till-fee-error-760.png` wraps the fee error but truncates the adjacent contact-phone required error (“A delivery needs a contact phone num…”). Retained isolated QA artifacts; QA settings/stock restored; dev stopped. Credential-bearing `temp/` evidence is never committed.

## Accepted old limits vs new unverified coverage

- **Accepted, not passed** (inherited from Phase 5 and unchanged): browser/native/physical printing, visual PDF legibility, genuine browser 1.3 text scaling, exhaustive keyboard traversal.
- **Live coverage now exists for the exercises above** (`temp/p6/qa/report.md`), but the unverified items stay unverified: zero-stock badge, legacy null location / null PO-VAT, clean-run completion-dialog Change, and the clean narrow order-fee error. The guards/audit/counter/badge Minors also remain proven by **automated tests**; golden inspection covers the single changed capture. The QA web build must use host-root `--dart-define=API_BASE_URL=http://127.0.0.1:8001` — the earlier `/api/v1`-suffixed override 404'd as `/api/v1/api/v1/…` and its shim run is historical only.
- **Retained Minors (recorded, not fixed here):** `common/numbering.py`'s "commits independently of the caller's insert" docstring wording; the "Void this quotation and issue a new one" 400 copy naming an action the product does not have; the archived refusal naming the variant when only the product is archived; the seed printing "Packaging repaired …" then "Packaging already seeded - skipping" on one run; B4's concurrency test covering quotations only; and no dedicated Flutter message for `INACTIVE_SELLING_UNIT` (the client filters active catalogue rows, the server refuses).
- **Baseline diagnostics, not introduced here** (review Minor #5; nothing was "fixed" by weakening a test and nothing is fixed in this close-out), split by whether the file is part of the phase diff:
  - **Untouched files:** `apps/pos/tests_exception_extra.py` — the pyright CLI baseline and this session's LSP+runner sweep report **12 errors** (L75-88, optional-access on DRF responses) while an earlier LSP-only probe of the same file reported **0 findings**, so the number is **tool-dependent baseline noise**, not a reproducible failure and not a global clean verdict; `apps/collectibles/models.py:138` reports **1 warning** (reverse-FK accessor).
  - **Changed file:** `apps/inventory/tests_supplier_payables.py` **is** modified by this phase (B2's tests) and carries **2 pyright warnings** at L496 on `with transaction.atomic()` — typing noise in test code, not a behavioural regression; it is not a baseline file.
  - Reports differ by tool run: CLI baseline and the LSP+runner sweep give 12 errors / 3 warnings across the three, an earlier LSP-only probe gave 0 for the test file. That makes them **tool-dependent baseline reports**, not a reproducible defect and not a clean verdict. Neither reading is evidence about Phase 6 behaviour.

## Documentation refreshed in this close-out

`ENDPOINTS.md` (quotations + sales-order rows: read-only `status`, 405 detail, audit rows, manager-only edit/delete, `INACTIVE_SELLING_UNIT`, locked numbering), `docs/SYSTEM_ATLAS.md` and `docs/system-atlas.html` (Phase 6 section, Phase 5's stale "archived unit accepted" gap retired, counts re-derived and unchanged: 48 routes · 23 VM classes / 24 files · 23 ApiClient service files / 29 · 15 feature directories · 42 models · 33 router paths), `planning/pos-evolution/MAP.md`, `AGENTS.md` status block, `docs/testing/QA-PROFILE.md`, and this note. `temp/` evidence stays local and gitignored.

## Next action

Record the completed QA result in the Phase 6 plan (done) and hand the phase to the owner for closure. No commit, push, dev startup/migration/reset, deployment or Phase 7 work is authorized; Phase 5 facts above it remain historical.
