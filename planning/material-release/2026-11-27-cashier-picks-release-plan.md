# Cashier picks how much to release — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The cashier chooses each line's "Give now" amount on a two-pane release screen; the server releases exactly that.

**Architecture:** `release_materials` takes an optional `{item_id: qty}` map, applied inside `_release_plan` under the existing token→request lock, so the shared-shelf rule uses the chosen amounts. Verify gains additive fields (status, unit, is_whole, unit_price). Flutter keeps a per-line chosen amount in `MaterialReleaseViewmodel` and the page becomes queue-left / request-right.

**Tech Stack:** Django 5 + DRF (tests via `qbt_db2` throwaway Postgres, `rt_qa.sh`), Flutter 3 (`flutter test --concurrency=2`).

**Spec:** `planning/material-release/2026-11-27-cashier-picks-release-design.md`

## Global Constraints

- No CPMS code change; `docs/integration/CPMS-CONTRACT.md` unchanged; read-back `released`/`outstanding` keep their meaning.
- `quantities` omitted, or a line not listed → that line releases its full `releasable` (old tills unchanged).
- Each chosen qty: `0 <= qty <= releasable`; whole units whole (`WHOLE_UNIT_QUANTITY`), others at most 2 decimals (`QTY_TOO_PRECISE`).
- New codes: `RELEASE_QTY_TOO_HIGH` (names the line and its current releasable), `UNKNOWN_RELEASE_LINE` (item not on this request, or listed twice). All chosen 0 → `NOTHING_TO_RELEASE` with "Nothing was chosen to release…". Every refusal before the first write.
- RELEASED only when every Available line is fully given; else PARTIAL, token stays valid.
- Two-pane at ≥ 1100 px wide; stacked below.
- No production DB; throwaway stacks only. No AI attribution in commits.

## Review Focus

1. Cashier lowers line 1 of two lines sharing a variant → line 2 may take the freed stock on the server (test in Task 1).
2. Stock drops between verify and release (another till sold some) → `RELEASE_QTY_TOO_HIGH`, nothing written, till reloads the request and says so (tests in Tasks 1 and 3).
3. A measured line given 2.5 of 12.5 KG → PARTIAL, outstanding 10.00, CPMS read-back unchanged in shape (test in Task 1).
4. Stepper typed above the cap or below 0, or 1.5 on a BAG line → clamped/refused on screen, never sent (test in Task 3).
5. All lines set to 0 → button disabled with the reason; no request sent (test in Task 3).

---

### Task 1: Backend — release takes chosen quantities

**Files:**
- Modify: `backend_django/apps/requisitions/services.py` (`_release_plan`, `release_materials`), `exceptions.py`, `serializers.py`, `views.py` (`material_release_view`)
- Test: `backend_django/apps/requisitions/tests_release_choice.py` (new)

**Interfaces:**
- Produces: `_release_plan(requisition, chosen: dict[int, Decimal] | None = None) -> list`; `release_materials(*, token_value: str, cashier, chosen: dict[int, Decimal] | None = None) -> dict`; `ReleaseQtyTooHigh(ValueError)` code `RELEASE_QTY_TOO_HIGH`; `UnknownReleaseLine(ValueError)` code `UNKNOWN_RELEASE_LINE`; `MaterialReleaseSerializer(token: UUID, quantities: list[{item: int, qty: Decimal(2dp)}] optional)`.

- [ ] **Step 1: Write the failing tests** in `tests_release_choice.py`, on `PartialReleaseBase` (10 BAG ordered at 10.00), posting `{"token", "quantities": [{"item": id, "qty": "x"}]}`:
  - `test_giving_less_than_the_shelf_leaves_the_rest_open`: 100 on shelf, give 4 → 201, `status` PARTIAL, `released_now` "4.00", `outstanding` "6.00", grand_total 40, stock 96, token not used.
  - `test_a_second_visit_with_the_rest_finishes_it`: give 4, then release with no quantities → RELEASED, token used.
  - `test_more_than_releasable_is_refused_and_writes_nothing`: shelf 4, ask 5 → 400 `RELEASE_QTY_TOO_HIGH`, detail contains "4", no SalesTransaction, stock 4.
  - `test_zero_everywhere_is_nothing_to_release`: give 0 → 400 `NOTHING_TO_RELEASE`, detail starts "Nothing was chosen to release".
  - `test_fraction_on_a_bag_is_refused`: "1.5" → 400 `WHOLE_UNIT_QUANTITY`; `test_three_decimals_refused`: on a KG line (`measure_per_base=40`) "0.125" → 400 `QTY_TOO_PRECISE`.
  - `test_unknown_or_repeated_line_is_refused`: another request's item id → 400 `UNKNOWN_RELEASE_LINE`; same id twice → same code.
  - `test_lowering_the_first_shared_line_frees_stock_for_the_second` (`SharedStockTests` setup: 12 on shelf, lines 10 + 5): give 7 on line 1, omit line 2 → line 2 releases 5, status PARTIAL (line 1 owes 3).
  - `test_measured_line_partial_by_choice`: KG line 12.5 ordered, give 2.5 → outstanding "10.00", stock down 0.0625 BAG.
  - `test_no_quantities_is_todays_behaviour`: covered by the existing `tests_partial_release.py` staying green.

- [ ] **Step 2: Run, expect failures** — `bash rt_qa.sh apps.requisitions.tests_release_choice` → FAIL (quantities ignored / no codes).

- [ ] **Step 3: Implement.** Serializer validates shape and 2dp max (field-shaped 400 for malformed). The view maps the list to `chosen = {item: qty}`, refusing duplicates with `UnknownReleaseLine`. In `_release_plan`, after computing a line's `releasable`, when `item.pk in chosen`: run `refuse_fractional_whole_unit(is_whole=..., qty=chosen, what=f"{variant} ({unit})")`; if `chosen > releasable` raise `ReleaseQtyTooHigh` naming the line and `releasable`; else `releasable = chosen`; decrement the shared `on_hand` by the CHOSEN amount. Ids in `chosen` that are not lines of this request → `UnknownReleaseLine` (checked before the loop). `release_materials` passes `chosen` through; when `chosen` is given and nothing is > 0, raise `NothingToRelease("Nothing was chosen to release. Set at least one Give now above 0. The token stays valid.")`. Verify still calls `_release_plan(req)` without `chosen`.

- [ ] **Step 4: Run** `bash rt_qa.sh apps.requisitions apps.integration` → all OK.

- [ ] **Step 5: Commit** `feat(release): the cashier chooses how much each line gives`.

### Task 2: Backend — verify carries status, unit, is_whole, unit_price

**Files:**
- Modify: `backend_django/apps/requisitions/services.py` (`verify_token`), `ENDPOINTS.md` (verify fields + release `quantities` + two codes)
- Test: `backend_django/apps/requisitions/tests_release_choice.py`

**Interfaces:**
- Produces: verify JSON `requisition.status` (e.g. "PARTIAL"); per item `unit` ("BAG"), `is_whole` (bool), `unit_price` ("10.00").

- [ ] **Step 1: Failing test** `test_verify_names_the_unit_price_and_status`: after giving 4, verify → `requisition.status == "PARTIAL"`, item `unit == "BAG"`, `is_whole is True`, `unit_price == "10.00"`; existing keys unchanged.
- [ ] **Step 2: Run** → FAIL (KeyError).
- [ ] **Step 3: Implement** the four additive keys; update `ENDPOINTS.md` rows for `tokens/verify/`, `requisitions/{id}/verify-release/`, `tokens/release/`.
- [ ] **Step 4: Run** `bash rt_qa.sh apps.requisitions apps.integration` → OK.
- [ ] **Step 5: Commit** `feat(release): verify names the unit, price and request status`.

### Task 3: Flutter — models, service, viewmodel amounts

**Files:**
- Modify: `flutter/lib/data/models/requisition.dart` (`VerifiedRequisitionItem`, `TokenVerification`), `flutter/lib/data/services/requisition_service.dart` (`release`), `flutter/lib/data/repositories/requisition_repository.dart`, `flutter/lib/features/pos/viewmodels/material_release_viewmodel.dart`
- Test: `flutter/test/features/pos/material_release_choice_test.dart` (new); fakes used by existing release tests gain the optional parameter.

**Interfaces:**
- Consumes: Task 1/2 wire fields.
- Produces: `VerifiedRequisitionItem.unit (String)`, `.isWhole (bool, default true when absent)`, `.unitPrice (double, 0 when absent)`, `.given (double) => quantity - remaining`; `TokenVerification.status (String)`; `RequisitionService.release(String token, {Map<int, double>? quantities})` sending `quantities: [{item, qty}]` only for listed lines; `MaterialReleaseViewmodel.giveNow(int itemId) -> double`, `setGiveNow(int itemId, double qty)` (clamped to `0…releasable`, whole units floored, others rounded to 2dp), `giveNowChanged(int itemId) -> bool`, `todayTotal -> double`, `stillOpenAfter -> List<({String name, double qty, String unit})>`, `confirmBlockedReason` gains "Set at least one Give now above 0." when every amount is 0; `release()` sends `quantities` for every releasable line; on `RELEASE_QTY_TOO_HIGH` it re-verifies the same request and sets `error` to "Stock changed since this request was opened. The amounts were updated — check them and release again."

- [ ] **Step 1: Failing tests:** `giveNow` starts at `releasable`; `setGiveNow(id, 99)` clamps to releasable; `setGiveNow(id, 1.5)` on a BAG line → 1; `setGiveNow(id, 2.555)` on KG → 2.56 is NOT accepted → 2.55 (floor to 2dp); all zero → `confirmBlockedReason == 'Set at least one Give now above 0.'`; `release()` passes `{id: 4}` to the fake repository; `todayTotal` = Σ giveNow × unitPrice; a fake `RELEASE_QTY_TOO_HIGH` triggers a second verify call and the message above.
- [ ] **Step 2: Run** `flutter test test/features/pos/material_release_choice_test.dart` → compile FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `flutter test --concurrency=2 test/features/pos/` → new green; failures identical to before (compare lists as in sell-by-measure).
- [ ] **Step 5: Commit** `feat(release): the till keeps a Give now amount per line`.

### Task 4: Flutter — two-pane release screen

**Files:**
- Modify: `flutter/lib/features/pos/views/material_release_page.dart`
- Create: `flutter/lib/features/pos/widgets/release_line_row.dart` (one line: name, "3 of 10 BAG given", progress bar, "7 still to give · up to 4 can go out now", stepper, status pill), `flutter/lib/features/pos/widgets/release_summary_bar.dart`
- Test: `flutter/test/features/pos/material_release_two_pane_test.dart` (new); update `material_release_page_test.dart` / `_partial_test.dart` expectations for new wording; regenerate goldens in `material_release_page_golden_test.dart`.

**Interfaces:**
- Consumes: Task 3 viewmodel API.
- Keys: `release-queue-pane`, `release-request-pane`, `give-now-<itemId>`, `give-now-minus-<itemId>`, `give-now-plus-<itemId>`, `release-summary`, `release-confirm`.

- [ ] **Step 1: Failing widget tests:** at 1400×900 both panes visible side by side (queue left of request); at 900×900 they stack; tapping minus on cement (releasable 4) shows 3, the hint "changed from 4", and summary "Giving today: 3 BAG Portland Cement 40kg"; "Still open after this:" lists the remainder; status pills read "Enough stock", "Short: up to 4 now", "Not available" with reason, "Already given"; all zero disables `release-confirm` and shows the reason; after release the receipt replaces the lines in the right pane and the queue stays.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** with the existing theme (`StatusBadge`, `AppSpacing`, `AppDialog` patterns); reuse `_ReleaseQueue` for the left pane and `_TokenField` under it; the receipt panel is today's step-3 content.
- [ ] **Step 4: Run** the release tests; `flutter test --update-goldens test/features/pos/material_release_page_golden_test.dart`, inspect a regenerated PNG, then `flutter analyze` clean and `flutter test --concurrency=2 test/features/pos/` failures identical to before.
- [ ] **Step 5: Commit** `feat(release): queue beside request, with Give now on each line`.

### Task 5: Verify across systems and in the app

- [ ] Backend full suite (`rt_qa.sh`) OK; Flutter full suite failures identical to master's list.
- [ ] Re-run `w_partial.py` (15/15) plus a new step: cashier gives 2 of 4 available → CPMS shows released 2 more, PARTIAL.
- [ ] Rebuild the QA app, click: open a partly released request, lower cement, check summary, release, receipt, queue refresh.
- [ ] Session note `docs/sessions/2026-11-27-release-cashier-picks.md`; commit `docs: release cashier picks — session note`.
