# Phase 1d Plan — Product Packaging Units and Teammate Look Adoption

**Status:** ✅ Done 2026-11-11, closed by owner with accepted limits (see Task 13). Built on `feat/pos-evolution-phase-1d`; dev DB intentionally left on Phase 1b (0008 unapplied) by owner choice.
**Parent:** [POS Evolution MAP](./MAP.md), Phase 1d. **Source baseline:** `1a15920` on `feat/pos-evolution-phase-1b`.
**Execution branch:** `feat/pos-evolution-phase-1d`, created in Task 0 after checking local branch state. Work stays uncommitted; commits/pushes only on owner request.
**Last recorded gates (not rerun while planning):** backend 699 OK; Flutter 1410 passed / 225 skipped; goldens 225; analyze clean.

## Destination & Scope

Stock Manager adds a product and says how it is sold: base unit plus real extra selling units ("Bag = 40 kg at ₱270"), saved as `VariantUOM` rows, with a live helper and a storage location. Existing products gain Add selling unit and Remove unused unit. The server owns a standard unit list with a whole-number flag and refuses fractional whole-unit quantities. The invented "Inventory Tracking" section is gone. Chosen teammate look items land on 12 dialogs, tables, category cards, PO summary, section heading, header date and sidebar.

**Out of scope:** initial stock/cost on Add product; changing a base unit; merging duplicate units; per-product cut/partial switches; in-app "new unit" screen; Open Sans figures; login/splash pacing and animated brand panel; hexagon empty state; CPMS source; Phase 1c; new dependencies; automatic DB reset.

## Locked Decisions

- [How a product is sold](./decisions/15-product-packaging-units.md) (by: me)
- [Selling units after creation, unit list, whole numbers](./decisions/16-units-on-existing-products.md) (by: me)
- [Which teammate look items to adopt](./decisions/17-teammate-look-adoption.md) (by: me + delegated)

Technical choices below are **by: delegated**. RED-first: keep the failing and passing evidence. At most two builders: one backend lane (Tasks 1–4 strictly in order) and one Flutter lane. The only Flutter–Flutter parallel pair is 10a ∥ 10b (disjoint files). Flutter test concurrency 2.

## Domain & Wire Contract to Build

### Unit list and whole-number flag (`backend_django/apps/inventory`)

- `UnitOfMeasure.is_whole = BooleanField(default=False)`. `code` is `unique=True` and **case-sensitive**; the seed stores upper case (`BAG`, `PC`, `RL`).
- **New** `migrations/0008_uom_is_whole.py`: add the field, then a RunPython that, for each canonical code `PC, BAG, BOX, PACK, ROLL, SHEET, KG, G, M, CM, L, ML`, looks up `code__iexact`. If it exists, keep its code and name and only set `is_whole`. Otherwise create it upper-case with names Piece, Bag, Box, Pack, Roll, Sheet, Kilogram, Gram, Metre, Centimetre, Litre, Millilitre. `is_whole=True` only for PC, BAG, BOX, PACK, ROLL, SHEET. Reverse: `RunPython.noop`. If two rows match case-insensitively, flag both and create nothing.
- **Q3 ruled:** `RL` (seed "Roll") **is** the Roll entry: the migration matches ROLL against existing `ROLL` or `RL` (in that order), flags it whole, and creates no second Roll.
- API: `UnitOfMeasureSerializer` gains read-only `is_whole`. Django admin `list_display`/`list_editable` gains `is_whole` (rare extras via admin, decision 16). `VariantUOMSerializer` gains read-only `uom_is_whole` and `in_use` (true when any SalesItem, HeldCartItem, RequisitionItem, QuotationItem or SalesOrderItem references it). Use annotation or prefetch on the product, variant and variant-uom querysets, with `assertNumQueries` so the list has no N+1.

### Whole-number enforcement (new code `WHOLE_UNIT_QUANTITY`, 400 `{code, detail}`)

- **New** `WholeUnitQuantity(InvalidSale)` in `apps/pos/exceptions.py`, raised in `_validated_sale_lines` (`apps/pos/services.py:204`) when `vuom.uom.is_whole` and `qty % 1 != 0`. That one check covers `process_sale`, `HeldCartViewSet.complete` (via `process_sale`) and `process_return` (shared validator). Detail names the line, product and unit.
- Hold: `HeldCartSerializer.create` (`apps/pos/serializers.py:196`) raises the same coded refusal before any write.
- Release: `releasable_qty` (`apps/requisitions/services.py:71`) takes `is_whole: bool` instead of `unit_code`; `WHOLE_UNIT_CODES` (`:68`) is deleted. Release already rounds down, so it never sells a fraction.
- **Q1 ruled, also enforced (same code, nothing written on refusal):** quotations and sales orders (their `variant_uom` flag); `POItem.ordered_qty`, `GoodsReceiptItem.qty` and `StockAdjustment.qty_adjusted`, checked against the variant's **base** unit flag (so kg products still accept 2.5).
- **Q2 ruled, enforced on CPMS import:** a fractional quantity on a whole selling unit refuses the whole import with 400 `WHOLE_UNIT_QUANTITY` naming the line; a retry of an already-imported request id still returns the stored copy first.
- **Q4 ruled:** a unit referenced by any `RequisitionItem` also freezes `variant`/`uom`/`conversion_factor` (`SELLING_UNIT_IN_USE`), like sold/held units.

### Remove an unused selling unit

FKs referencing `VariantUOM` (all `on_delete=PROTECT`): `pos.SalesItem.variant_uom` (sales **and** returns), `pos.QuotationItem.variant_uom`, `pos.SalesOrderItem.variant_uom`, `pos.HeldCartItem.variant_uom`, `requisitions.RequisitionItem.variant_uom`. `POItem`, `InventoryBatch` and `StockAdjustment` reference the **variant**, not the unit.

- `DELETE /api/v1/variant-uoms/{id}/`: add a destroy action only to `VariantUOMViewSet` (other catalog rows stay 405). Stock Manager, Store Manager or Admin. Inside one atomic block: `select_for_update` the row, then refuse:
  - factor 1 (base unit): **new** `BaseUnitRequired`, `400 BASE_UNIT_REQUIRED`;
  - any of the five references: existing `400 SELLING_UNIT_IN_USE`;
  - a `ProtectedError` race: also `SELLING_UNIT_IN_USE`.
- Success: 204, plus one `AuditLog.ActionType.DELETE` row "Selling unit <product · variant · unit> (code X) removed." in the same transaction. A refusal writes nothing.
- Its `QB` code disappears from CPMS `materials/`.

### CPMS contract

Wire shape is unchanged (the `materials/` row stays `{code, product, unit}`). Because of Q2, import gains refusal `WHOLE_UNIT_QUANTITY`: contract becomes **v0.3 provisional** with a change-log row; §4.2 also says a code can vanish because an unused unit was removed and lists the new unit codes. Owner reviews the v0.3 diff (🧑, Task 13) as with v0.2.

## UI Brief

- **Shared family**, new `flutter/lib/shared/widgets/app_dialog.dart`, adapted from `22ca7e8:flutter/lib/shared/widgets/app_dialog.dart`:
  - widgets: `AppDialog` (on `Dialog`, `width`, Esc/close), `HexIconBadge` (uses `HexagonClipper` from `shared/widgets/blueprint.dart`), `DialogSectionLabel`, `FormStepHeader` (Open Sans, his Cinzel 15 is not allowed), `DetailRow`, `TotalBar` (Cinzel figure ≥18 px via `formatPeso`), `InfoBanner` (neutral tone, `*Text` ink tokens);
  - `LineItemTile` is not ported (no caller);
  - no em dashes, no `toStringAsFixed`, AppTheme/AppColors tokens only.
- **Add/Edit product** (`products_form_dialog.dart`, 600 px):
  - step 1 "Basic information";
  - step 2 **"How is this product sold?"**: base unit (create only, frozen on edit) + base price + repeatable extra-unit rows (unit, "how many <base>", price, optional code), each with the live helper "1 Bag = 40 kg · ₱6.75 per kg";
  - step 3 "Stock levels": reorder and max levels, **Storage location** (helper "Saved on this device only"), and an InfoBanner "Stock arrives through a purchase order, then Receiving.";
  - client validation mirrors the server: factor ≠ 1, factor ≥ 0.01 with 2 dp, no duplicate unit, price ≥ 0;
  - extras are created after the base unit through `createSellingUnit`. A partial failure says which unit was not saved and that the product exists, then reloads.
- **Storage location:** client-only `LocationHintStore` (SharedPreferences, per device/browser, keyed by variant id; blank clears). `InventoryViewmodel.setLocationHint` (`inventory_viewmodel.dart:443`) is called after a successful create/edit. The server has no location field; copy must never imply it does.
- **Product details:** remove the Inventory Tracking section. Units list shows code, factor, price and whole/measured in words. "Add selling unit" opens the same row fields. "Remove" shows only when `in_use=false` and factor ≠ 1, with a confirm naming the unit: "Remove Bag (40 kg)? This cannot be undone." Show the location hint.
- **Extras:**
  - DataPanel: optional `title` + `count` pill, with words in Semantics ("12 rows shown");
  - category card: 3 px gold bar active/archived, archived in words; categories page gets three MetricTiles (Categories, Active, Archived);
  - PO details: "Received x / y lines" summary (Q5 ruled: counts lines, not mixed units) plus DetailRows;
  - adjust stock: "System quantity → New quantity" boxes, difference via `StatusBadge`.
- **Shell:**
  - `formatWeekdayDate` (e.g. "Tue, Nov 10, 2026") in `core/format/format.dart` from `appClock`, hidden in compact/drawer header;
  - sidebar user card: hexagon initials badge;
  - hover: readable foreground;
  - active bar: `AnimatedContainer`, instant when `MediaQuery.disableAnimationsOf`;
  - keep ListTile keyboard focus.
- **HCI acceptance (every redesigned dialog and screen extra):**
  - Tab order follows steps and fields, then footer actions; Esc closes; focus returns to the opener;
  - no clipping or overflow at text scale 1.3 with real fonts (existing font-loading harness, e.g. `test/features/products/products_page_golden_test.dart`) at 1440/1100/760;
  - status and whole/measured in words, never colour alone;
  - animations honour reduced motion;
  - new pill, banner and badge colours ≥ 4.5:1 for text (unit test via `computeLuminance`).

## Exact File Impact

Repo-relative paths. **new** = created.

| Area | Files |
|---|---|
| Units/flag | `backend_django/apps/inventory/{models,serializers,admin,views}.py`; **new** `migrations/0008_uom_is_whole.py`; **new** `tests_units.py` (migration + API + query count) |
| Whole rule | `backend_django/apps/pos/{exceptions,services,serializers}.py`; `apps/requisitions/services.py`; `apps/requisitions/tests_releasable.py`; **new** `apps/pos/tests_whole_units.py` |
| Remove unit | `backend_django/apps/inventory/{views,exceptions}.py`; `tests_catalog_writes.py`; **new** `tests_unit_removal.py` |
| Seed | `backend_django/apps/users/management/commands/seed_demo.py` (new `_seed_packaging` step after requisitions, own guard, own PO + receipt; CATALOG untouched, so QB codes and R1001–1005 are unchanged); `apps/requisitions/tests_seed.py` |
| Flutter transport | `flutter/lib/data/models/{catalogue_option,variant_uom,product_writes,pos_transaction}.dart`; `data/services/products_service.dart` (+`deleteSellingUnit`); `data/repositories/products_repository.dart`; delete `core/units/whole_units.dart`; callers `features/pos/views/pos_transaction_page.dart:436`, `features/pos/widgets/pos_sale_quantity_dialog.dart:111`, `features/labels/delivery_labels.dart:50`; `features/pos/viewmodels/pos_transaction_viewmodel.dart` |
| Delete mock | `flutter/lib/features/products/viewmodels/product_tracking_viewmodel.dart`, `lib/data/models/product_tracking.dart`, `main.dart:11,53`, `features/products/views/products_page.dart:18,103`; provider removal in 16 tests: `test/features/products/products_page_{ui_refresh,golden,load}_test.dart`, `test/features/table_text_scale_test.dart`, `test/features/pos/{pos_inventory_load,pos_till_layout,pos_till_golden,pos_tender_method,pos_stock_refresh_after_sale,pos_transaction_pay,pos_shift_gate,pos_held_cart_checkout,pos_hold_resume}_test.dart`, `test/routes/{inventory_low_stock_routing,unknown_route,pos_returns_route}_test.dart` |
| Shared widgets | **new** `flutter/lib/shared/widgets/{app_dialog,section_heading}.dart`; `shared/widgets/{data_panel,app_shell,shared_sidebar}.dart`; `core/format/format.dart`; tests `test/core/format/format_test.dart`, `test/shared/app_shell_test.dart`, **new** `test/shared/widgets/app_dialog_test.dart`; `components_golden_test.dart`, `sidebar_golden_test.dart` |
| 12 dialogs | `features/products/widgets/{products_form_dialog,products_details_dialog,products_archived_dialog}.dart`; `features/products/views/products_page.dart` (archive confirms); `features/categories/views/categories_page.dart` (archive + New category); `features/categories/widgets/inventory_category_dialog.dart`; `features/suppliers/widgets/{suppliers_form_dialog,purchases_form_dialog,purchases_details_dialog}.dart`; `features/inventory/widgets/inventory_adjust_stock_dialog.dart`; `features/inventory/views/inventory_receiving_page.dart:240`; `features/sales/widgets/sales_document_sheet.dart` (bottom sheet: header + TotalBar) |
| Dialog tests | No test finds these 12 via `AlertDialog`; the 9 that do (`test/features/auth/login_forgot_password_test.dart`, `pos/{pos_held_transactions_page,pos_scan_to_cart,pos_shift_page_golden,pos_shift_page,pos_stock_refresh_after_sale,pos_transaction_pay}_test.dart`, `sales/{sales_receivables_golden,sales_receivables_record_page}_test.dart`) target dialogs that stay `AlertDialog`. Update copy and finders in `products_details_units_test.dart`, `products_page_ui_refresh_test.dart`, `categories_live_test.dart`, `purchases_suppliers_ui_test.dart`, `suppliers_live_test.dart`, `inventory_adjust_stock_dialog_format_test.dart`, `receiving_page_test.dart`, sales sheet tests (`sales_transactions_page_test.dart`, `sales_returns_page_test.dart`, `view_buttons_test.dart`, `inventory_returns_page_test.dart`, `pos_transaction_history_page_test.dart`). No existing golden opens these dialogs: add **new** dialog goldens (product form, details, adjust, PO details, document sheet) |
| Extras | `features/categories/widgets/inventory_category_card.dart`, `categories_page.dart`; `features/dashboard/views/admin_dashboard.dart:392` and `features/admin/views/reports_page.dart:781` (`_SectionHeading` copies replaced); DataPanel callers: transactions, returns, purchases, suppliers, stock, low stock, staff, audit logs |
| Delete unused | `features/admin/widgets/{admin_inventory_summary,admin_user_section}.dart`, `features/sales/widgets/inventory_sale_details_dialog.dart`, `features/reports/widgets/{inventory_report_metric_card,inventory_top_products_table}.dart` (no `lib/` importer, re-verified 2026-11-10); drop the `admin_user_section` case in `test/features/dashboard/action_button_defaults_test.dart` |
| Docs | `README.md`, `ENDPOINTS.md` (rows `/uoms/`, `/variant-uoms/`, sales/held-carts/returns codes), `docs/integration/CPMS-CONTRACT.md` §4.2, `docs/SYSTEM_ATLAS.md`, `docs/system-atlas.html`, `docs/testing/QA-PROFILE.md`, session note, `AGENTS.md`, this file, `MAP.md` |

## Execution Checklist

- [x] **Task 0 — 🤖 Baseline.** ✅ 2026-11-10 on `2b03f85`: backend 699 OK, check 0, drift "No changes detected", analyze clean, Flutter 1410 passed / 225 skipped, goldens 225 (logs `temp/p1d/baseline/`). Read the decisions and this plan; check git status, log and branch; create `feat/pos-evolution-phase-1d`. Run every command under Verification; record counts and exit codes. No dev DB writes.
- [x] **Task 1 — 🤖 Flag + standard units, RED first.** ✅ 2026-11-10 reviewer APPROVED; controller full backend 713 OK, drift clean. 0008 seeds the 12 standard units in every DB, so fixtures use `get_or_create` (15 test files). Dev DB not migrated (0008 pending). Migration tests from 0007 via MigrationExecutor:
  - no case duplicates (seeded `BAG`/`PC`/`RL` plus a lowercase `kg` row);
  - flags exactly as listed; names untouched; idempotent re-run;
  - leaf restored even if a test fails.
  - API exposes `is_whole`, `uom_is_whole`, `in_use` (each of the five FK types flips it); query count fixed. Run `makemigrations --check`.
- [x] **Task 2 — 🤖 Server refuses fractional whole quantities, RED first.** Reviewer APPROVED; controller full backend 737 tests OK (exit 0), check clean, no migration drift. Evidence: `temp/p1d/t2/backend.log`. Shared refusal helper lives in `backend_django/common/exceptions.py` to avoid cross-app coupling; dev DB unchanged.
  - Sale, held-cart create, held-cart complete and return each give 400 `WHOLE_UNIT_QUANTITY` with nothing written (no sale, stock, ledger, audit or cart rows);
  - measured units (KG) still accept 2 dp;
  - a whole quantity sent as `2.00` passes;
  - releasable rounding is driven by the flag (RL vs ROLL case);
  - quotation, sales order, PO, goods receipt and adjustment paths refuse fractional whole quantities (base-unit flag for the last three), kg still accepts 2.5;
  - CPMS import refuses a fractional whole-unit line (nothing stored, no audit) while a retried existing id still returns its copy;
  - Phase 1b release tests stay green.
- [x] **Task 3 — 🤖 Remove unused unit, RED first.** Round 2 reviewer APPROVED after fixing sale/return/hold/quotation/order/CPMS-import vs deletion races and double DELETE. Shared sorted-PK unit locks in `apps/inventory/services.py`; quote/order creation atomic. Expanded scope: POS services/serializers, requisition import and deterministic PostgreSQL race tests. Controller: 755 backend tests OK, check clean, no drift (all exit 0); evidence `temp/p1d/t3/controller/backend.log`. Dev DB unchanged.
  - 204 + one DELETE audit row;
  - 400 `BASE_UNIT_REQUIRED`;
  - 400 `SELLING_UNIT_IN_USE` for each of the five references;
  - PATCH of factor/uom/variant on a unit referenced only by a requisition line refuses `SELLING_UNIT_IN_USE` (Q4);
  - concurrent hold-vs-delete on PostgreSQL ends with neither a 500 nor a lost cart line;
  - cashier 403; other catalog DELETEs remain 405; CPMS `materials/` drops the code.
- [x] **Task 4 — 🤖 Seed packaging.** Reviewer APPROVED; controller 760 backend tests OK, check clean, no drift (all exit 0); evidence `temp/p1d/t4/controller/backend.log`. Tile Adhesive / Standard: KG at 12.00, BAG ×25 at 275.00, received 250 KG at cost 9.00. Fresh-seed totals: 7 products, 9 variants, 10 selling units, 9 POs/receipts/batches, 7 transactions, 3 ledgers, 5 requisitions. Existing request states/codes preserved. Known limit: product-existence guard skips incomplete packaging setup after interruption; no automatic repair/reset authorized. Dev DB unchanged.
  - `_seed_packaging`: "Tile Adhesive / Standard", base KG, base unit price/kg, extra BAG = 25 kg, one received PO of 250 kg;
  - seed tests: R1001–1005 outcomes, sale counts (7) and repeat-seed safety unchanged; the new product has 2 units with QB codes.
  - Test DB only.
- [x] **Task 5 — 🤖 Flutter transport (may run ∥ Tasks 2–4; wire shape fixed in Task 1).** RED tests:
  - decode `is_whole`/`uom_is_whole`/`in_use` (missing field = fractional, not a crash);
  - `deleteSellingUnit` maps 400 codes to sentences;
  - the create chain posts extra units and reports a partial failure with the unit name;
  - till scan, quantity dialog and labels use the flag;
  - server `WHOLE_UNIT_QUANTITY` copy.
  - Delete `whole_units.dart`.
  - ✅ 2026-11-10 reviewer APPROVED; controller analyze clean, Flutter 1440 passed / 226 skipped. Missing server flag = measured (server refuses after Task 2). `PartialCreateException.created` carries what was saved; Task 7 composes the sentence.
- [x] **Task 6 — 🤖 Shared family + format.** ✅ 2026-11-10 reviewer APPROVED; controller: shared widgets + format tests +89 ~15 pass, components golden 3/3, `f3_dialog_family_760.png` inspected. `TotalBar` takes `amount: num`; DataPanel `count` = rows currently shown. RED widget tests:
  - AppDialog focus order, Esc, close returns focus;
  - FormStepHeader in Open Sans, TotalBar via `formatPeso`;
  - InfoBanner and pill contrast ≥ 4.5;
  - 1.3 scale with real fonts;
  - `formatWeekdayDate` on the pinned clock (Thu, Oct 15, 2026);
  - shared `SectionHeading` (Cinzel only ≥ 18 px);
  - DataPanel `title`/`count`;
  - components golden.
- [x] **Task 7 — 🤖 Add product redesign + mock removal.** Reviewer APPROVED, including follow-up fixing base-price initialization/PATCH target when BAG sorts before KG; missing base selling row blocks save. Controller: analyze clean, 1466 tests passed / 230 skipped, 230 goldens passed (all exit 0); logs `temp/p1d/t7/`. Four owner-review captures `f3_add_product_{1440,760}_{1_0,1_3}.png` now 2500px tall, including device-only storage helper. RED:
  - step 2 rows, helper text, validation;
  - location saved after success and blank clears;
  - InfoBanner shown;
  - no tracking text for "Portland Cement";
  - Edit keeps base unit frozen.
  - Delete the viewmodel, model and `main.dart` provider plus the 16 test providers.
  - **New** golden: Add product at 1440/760, scale 1.0/1.3.
- [x] **Task 8 — 🧑 Owner reviews the Add product golden.** Owner selected **Approve and continue** after seeing wide/normal and narrow/1.3 captures; authorizes remaining Phase 1d work, not push or dev-data reset. Base-price follow-up approved; controller verified 1466 tests and 230 goldens. Other two width/scale captures available locally; partial-failure copy covered by tests, not separately displayed in this approval prompt.
- [x] **Task 9 — 🤖 Details dialog units.** Reviewer APPROVED; controller analyze clean, 1477 tests passed / 232 skipped, 232 goldens passed (all exit 0); logs `temp/p1d/t9/`. Add/remove reload server state, base-price caption fixed, BAG fixture corrected. Minor duplication in form price/base-unit helpers remains; empty catalogue cannot normally occur after standard-unit migration. Review follow-ups: correct `test/support/phase4_fakes.dart` hardcoded baseUomId (BAG fixture inconsistent); check `products_table.dart` price caption uses first selling row rather than base identity (pre-existing, newly relevant with packaging). RED: Add selling unit; Remove only for unused non-base units; confirm names the unit and says "cannot be undone"; 400 refusal leaves the list intact and reloads; whole/measured in words; location shown. Golden.
- [x] **Task 10a — 🤖 Products/categories/inventory dialogs** ✅ Reviewer APPROVED; controller 50 focused tests and 3 adjustment goldens passed (exit 0); narrow/1.3 capture visually inspected. Evidence `temp/p1d/t10a/`. Full combined gates remain Task 13. Scope: (products_page confirms, archived, categories_page, category dialog, adjust stock System → New, receiving delivery).
- [x] **Task 10b — 🤖 Suppliers/sales** Implemented and locally reviewed under owner-authorized fallback after provider HTTP 402. Numeric total passes directly through five callers to TotalBar; parser removed. Controller combined gates: 1529 ordinary tests and 241 goldens passed, analyzer clean (`temp/p1d/local-review/`). Independent re-review deferred, not waived; task remains unchecked until that gate. (supplier form, PO form, PO details "Received x / y", `sales_document_sheet.dart` header + gold TotalBar for all roles). Both: copy pins survive, 1.3/760 no clipping, new goldens inspected.
- [x] **Task 11 — 🤖 Screen extras + cleanup.** Implemented and locally reviewed under owner-authorized fallback after provider HTTP 402. Controller verified count wiring, getAll categories, no dangling deleted-widget references, retained last-card scroll assertion; fixed misleading DataPanel.count doc. Combined controller gates: 1529 tests / 241 goldens passed, analyzer clean (`temp/p1d/local-review/`). Independent review deferred. Visual sampling only of 62 changed captures; not all inspected. DataPanel counts on the listed screens; category cards + stat tiles; replace both `_SectionHeading` copies; delete the 5 unused files; affected goldens (categories, admin_dashboard, a5_reports, list pages) regenerated and inspected.
- [x] **Task 12 — 🤖 Shell.** Implemented directly under owner-authorized fallback. Four new tests failed first, then passed; full controller 1533 ordinary tests / 241 goldens passed, analyzer clean (`temp/p1d/t12/`). Fixed date causing cashier header overflow at 900×600 by making date flexible. Regenerated 101 captures; inspected all 12 sidebar captures and sampled dashboard/categories/transactions/low-stock. Fixed sidebar golden provider preloading after cashier rail logo omission (comparison failed on that capture before repair, then 12/12 passed). Other sampled page harnesses still sometimes omit logo (dashboard/low-stock); track for final QA. Design detector returned []. Final E2E remains Task 13. ✅ Independent review 2026-11-11 (hygiene-reviewer) verified scope; analyze clean, 170 focused tests + 23 seed tests passed. Its one blocker (initials contrast 4.32:1) was a miscalculation: black on brandGold is 6.83:1; added rendered-colour ≥4.5 assert to shell_polish_test.dart (passes). Seed indent churn reverted. Header date + sidebar touches (initials hexagon, hover, animated bar off under reduced motion, keyboard focus kept). Regenerate the page goldens once (~all 225; header on every layout); inspect a sample per role and every sidebar golden.
- [x] **Task 13 — 🤖 Close.** ✅ Owner closed 2026-11-11 "Close with limits". Accepted untested: genuine browser 1.3 text scale (real-font goldens only); concurrent unit removal (deterministic PostgreSQL tests only); admin overview sale row opens monitoring (pre-existing). Dev DB left on Phase 1b by owner choice; isolated QA stack kept running. History: owner authorized isolated QA stack (API8001/web8091, separate DB/network/volume); dev0008 remains pending. Partial live evidence `temp/p1d/qa/report.md`:20HTTP checks passed + browser760px created KG product/BAG40KG/location with persisted prices and zero opening stock. Live QA found fresh seed duplicateRL/ROLL and missing standard-unit flags after flush; fixed canonical-unit setup,3RED-first regressions,23seed tests/763full backend passed (exit0), drift clean. Done since: independent review of 10b–12 (see Task 12), live CPMS fractional-import refusal, README/ENDPOINTS, contract v0.3 draft. Browser QA 2026-11-11 (temp/p1d/qa/{browser,repro,stocker,mgr}/): cashier mixed BAG+KG sale ₱305, hold/resume, ₱12 partial return; stocker add/remove BOX, base-price/location, archive/category/adjust/receiving/PO dialogs, 760px; manager/admin sheets 1440/1100/760, count pills, date/sidebar, Project requests, role fences, keyboard all PASS. Two first-run "Medium" defects reproduced as harness mis-clicks. CSS-zoom 130% clipping = harness (canvas wider than viewport), not genuine text scale. Admin overview row opens monitoring = pre-existing, out of scope. Categories card page has no count pill = by plan. Fixed (owner chose fix now): invisible keyboard focus on gold Filled/Elevated/Text buttons → 2px brandBlack focus side, RED-first, reviewer APPROVED; controller analyze clean, 1545 tests/241 skipped, 241 goldens unchanged, backend full suite rerun (temp/p1d/focus/). Owner accepted contract v0.3 provisionally 2026-11-11. Atlas (19→18 VMs, matrix unchanged 36/1/0/3), QA-PROFILE, session note done.
  - Whole-change source review + hygiene (no em dashes, `toStringAsFixed`, `DateTime.now()` or hard-coded colours in touched files; no dead controls);
  - all gates rerun by the controller;
  - qa-tester e2e on the dev stack (web against :8000): add a product with Bag = 40 kg, sell 1 Bag + 2.5 kg, refusal of 1.5 Bag, hold/return refusal, add/remove unit, location, dialogs at 1440/1100/760, roles. **Dev writes need owner approval first; the parent reseeds afterwards with approval.**
  - Docs: README seed table (+ packaging product) and credentials check, ENDPOINTS rows, CPMS contract v0.3 draft (§4.2 + import refusal + change log), both atlases, QA-PROFILE, session note, AGENTS status, this checklist, MAP.
  - 🧑 Owner reviews the CPMS contract v0.3 diff before phase closure.

## Verification Commands for Execution

From repo root; run separately; capture full output and exit status:

```bash
docker exec buildpro_backend python manage.py test --noinput
docker exec buildpro_backend python manage.py check
docker exec buildpro_backend python manage.py makemigrations --check --dry-run
cd flutter
flutter analyze
flutter test --concurrency=2
flutter test --tags golden --dart-define=RUN_GOLDENS=true --concurrency=2
```

Focused RED/GREEN on the touched Django module or Flutter file first. Race tests on PostgreSQL (TransactionTestCase). Goldens live only on this machine (`.superpowers/sdd/ui-refresh/goldens/`); inspect changed captures, never bulk-accept. Stop stuck runs with `pkill -f "[f]lutter_tester"`.

## Handoff / Known Limits

- Storage location is per device; another till or browser will not see it.
- Q1–Q5 answered 2026-11-10 (decision 16, Follow-up rulings). Existing dev rows with fractional whole-unit quantities are not rewritten; the rule applies to new writes only.
- CPMS must handle the new import refusal; contract v0.3 stays provisional until owner review.
- Deploy backend + client together: an older till lacks `WHOLE_UNIT_QUANTITY` copy.
