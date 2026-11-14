# Phase 3 Plan — Cashier

**Spec:** [MAP](./MAP.md) decisions [Release shift](./decisions/03-release-shift.md), [Returns policy](./decisions/05-returns-policy.md). Items marked **(U)** come from the user's 2026-10-24 report (broken staff list, dead buttons); **(R)** are research findings, ledgered as rulings.
**Branch:** `feature/backend-integration`. **BASE:** `12c8eb8`. **Baseline:** backend 333/333 (`manage.py test --noinput`), flutter 565/565.

## Global constraints

- Same harness rules as [Phase 1](./phase-1-plan.md#global-constraints) and [Phase 2](./phase-2-plan.md#global-constraints): tests run in docker with `--noinput`, `content_type='application/json'` for nested writes, RED first (an assertion failure, not an import error), one commit per task with its tests, no CPMS, no `temp/`.
- Phase 2 security stays intact: cashier scope (404 for another cashier's rows), token secrecy, immutable sales, append-only audit. Every new money/stock event writes exactly one audit row inside its transaction.
- Every new refusal is a stable `{code, detail}` 4xx. Never a 500.
- `ENDPOINTS.md` is the single home for the API contract. Update every row you change.
- **No dead controls:** a button either does something real, or it is removed. Don't leave a disabled placeholder unless the label says why.

## Task 0 — Staff list crash + dead-control sweep (Flutter) **(U)**

**Files:** `lib/data/models/user.dart` (+ `role.dart` if needed), admin user-management widgets, `lib/features/sales/views/{sales_dashboard,sales_quotations,sales_orders,sales_returns}_page.dart`, `lib/features/auth/views/login_page.dart`, `lib/core/layout/{sales,inventory,admin}_skeleton_layout.dart`, `lib/features/dashboard/widget/{admin,inventory}_action_button.dart`, `lib/features/admin/widgets/{admin_user_action_button,admin_report_filters}.dart`.

1. **Staff list:** `GET /users/` legitimately returns `role: null` for an account with no group (Django admin, `createsuperuser`, an account whose role was removed). One such row currently throws `FormatException('Missing required object field "role"')`, and the whole User Management list fails with it. Make `User.role` nullable (or a sentinel "No role"), and show a "No role" badge. Role-dependent actions on that row must still work: assigning a role is exactly how an admin fixes it. Other required fields still fail loudly.
2. **Dead buttons:** wire each one to something real or remove it:
   - Sales Quotations "New quotation" and Sales Orders "New sales order": **remove**. The sales-manager decision made these views read-only.
   - Sales Returns "New customer return": **remove**. Cashiers return from the till Returns tab (Task 4); the manager's unlinked-return screen is Phase 5.
   - Sales Returns row "View": open a **read-only details sheet** (reference, original sale, lines, qty, reason, refund, cashier, date), using the same pattern as the transactions View sheet.
   - Sales Dashboard "This month": it filters nothing, so replace it with a non-interactive label/chip stating the period the dashboard actually shows.
   - Login "Forgot password?": no self-service reset exists, so open a dialog saying to ask a System Administrator to reset the password.
   - "Notifications" in the sales, inventory and admin shells: one shared `NotificationsButton` that opens a **read-only** sheet of unresolved alerts from `GET /api/v1/alerts/` (readable by every authenticated user), with loading, empty and error+retry states. Resolving alerts stays Phase 4.
   - `AdminReportFilters`: unused, so delete it.
   - `AdminActionButton`, `InventoryActionButton` and `AdminUserActionButton` currently do `onPressed ?? () {}`. Pass `null` through instead, so a button without a callback renders **disabled** rather than silently dead.
3. **Guard test:** add `test/no_dead_controls_test.dart`. It scans `lib/**.dart` and fails on `onPressed: () {}`, `onPressed: () => {}`, `onTap: () {}`, `onChanged: (_) {}` and `?? () {}`, so a dead button can't come back unnoticed.

**RED tests:** user list JSON with a `role: null` row → list renders, the row shows "No role", and the other rows render too (today: FormatException); widget test for each rewired control (View sheet opens with data, Forgot password dialog, Notifications sheet lists alerts / empty / error); the guard test fails on the current tree.

## Task 1 — Release requires an open shift (decision 03, backend)

**Files:** `apps/requisitions/services.py` (`release_materials`), `apps/requisitions/views.py` (release error mapping), `apps/requisitions/tests_security.py` or new `tests_release_shift.py`.

1. Inside the atomic block, after locking the token and **before any write**, read the releasing cashier's OPEN shift. If there is none, raise `NoOpenShift` → 400 `{code:'NO_OPEN_SHIFT'}`. Set `SalesTransaction.shift` on the release.
2. In the Z-reading, the release counts in `transaction_count` and `gross_sales`. `expected_drawer` doesn't change, because a release creates a collectible, not a cash Payment. Verify this; don't assume it.
3. Concurrent or double release of one token: exactly one succeeds. The token row lock already exists; prove the second gets 400 and stock moved once.

**RED tests:** release without an open shift → 400 NO_OPEN_SHIFT, token `is_used=False`, batch qty unchanged, no SalesTransaction / receipt / ledger / RELEASE audit row; release with a shift → `txn.shift == open shift`, Z count +1, gross includes the release total, `expected_drawer` unchanged; second release of the same token → 400 and one deduction.

## Task 2 — Cashier returns policy + debt-first refunds (decision 05, backend)

**Files:** `apps/pos/services.py` (`process_return`), `apps/pos/views.py` (create RETURN path, new endpoints), `apps/pos/exceptions.py`, `apps/pos/serializers.py`, new `apps/pos/tests_returns_policy.py`; fix existing return tests' fixtures where the new rules apply (list every fixture change).

1. **Open shift required** for every return → 400 `NO_OPEN_SHIFT` before any write. This replaces the "attach if present" rule.
2. **Linked required for non-managers:** a return without `original_transaction` from a user without the manager/admin role → 403 `{code:'UNLINKED_RETURN_FORBIDDEN'}`. Manager/admin unlinked returns remain allowed (their screen is Phase 5).
3. **Reason required:** non-empty `reason` (max 255) on every return → 400 `RETURN_REASON_REQUIRED`. Store it in `SalesTransaction.notes`.
4. **Not returnable:** an original with `source=REQUISITION` → 400 `RELEASE_NOT_RETURNABLE`. Return-of-return and non-COMPLETED originals stay refused, now with stable codes (`RETURN_OF_RETURN`, `ORIGINAL_NOT_COMPLETED`).
5. **Qty cap by selling unit (R):** for each line, the cumulative returned qty of that `VariantUOM` across all returns linked to the original must not exceed the qty sold on the original → 400 `RETURN_QTY_EXCEEDED` with `{variant_uom, sold, already_returned, requested}`. Today the cap exists only through deduction rows, so pre-linkage sales without deduction rows have **no cap**. Lock the original transaction row (`select_for_update`) at the start, so concurrent returns serialize and can't exceed the cap together.
6. **Debt first:** if the original has a CollectibleLedger with `balance_due > 0` (OPEN/PARTIAL/OVERDUE), lock it, reduce `balance_due` by `min(return_value, balance_due)`, set status PAID at 0 (else PARTIAL), and record the reduction as a `CollectiblePayment` (`payment_method='RETURN_CREDIT'`, `official_receipt_no` = the return's `transaction_no`, `processed_by` = cashier). The ledger history then explains the drop. Only the **excess** is refunded: the return's `Payment` row is `-excess` in the requested method. Write no Payment row when the excess is 0, and check that `compute_z_reading` stays correct (cash refunds = cash excess only).
7. **Restock** stays per `SalesItemDeduction` (FIFO cost basis); unchanged.
8. **Response:** the 201 body adds `refund_summary: {return_value, debt_reduced, cash_refund, refund_method, ledger_id, ledger_balance}`. The RETURN audit description names the return number, the original number, debt reduced and cash refunded.
9. **Lookup endpoints for the till (R):**
   - `GET /transactions/?q=<text>`: case-insensitive exact match on `transaction_no` or receipt `or_number`, applied **after** the cashier scope (another cashier's sale → empty result).
   - `GET /transactions/{id}/returnable/`: through the scoped queryset (another cashier's → 404). Returns `{transaction_no, customer, source, returnable: bool, reason_if_not, lines:[{variant_uom, name, uom, sold_qty, returned_qty, remaining_qty, unit_price}], open_debt}`.

**RED tests (decision 05 list + extras):** cashier unlinked → 403; qty above remaining → 400 RETURN_QTY_EXCEEDED (including across two sequential returns, and for a sale with no deduction rows); no shift → 400 and no row/stock change; no reason → 400; release original → 400 RELEASE_NOT_RETURNABLE; **credit sale 1000 with 600 unpaid, return 800 → ledger balance 0 + PAID + one RETURN_CREDIT payment of 600, cash refund 200, Z `cash_refunds` 200**; full-paid sale return → cash refund = value, ledger untouched; partial debt return smaller than debt → refund 0, no Payment row, ledger PARTIAL; manager unlinked with reason → 201; cashier `?q=` on another cashier's number → empty; `returnable/` on another cashier's sale → 404; exactly one RETURN audit row per success, none per refusal.

## Task 3 — Shift close advisory (backend)

**Files:** `apps/pos/views.py` (shift `current`, close), `apps/pos/serializers.py` (`ShiftSerializer`), tests in `apps/pos/tests.py` or a shift test module.

1. `ShiftSerializer` gains read-only `held_cart_count`: the number of HeldCarts whose `cashier` is the shift's cashier. Returned on `current` and on close.
2. Close is **not** blocked by held carts (advisory, decision 06 record-and-warn). The Z-reading payload of a close also carries `held_cart_count`.

**RED tests:** cashier with 2 held carts → `current.held_cart_count == 2`; close succeeds and the response says 2; another cashier's carts are not counted.

## Task 4 — Till: Returns tab, release shift gate, close advisory (Flutter)

**Files:** `lib/features/pos/widgets/pos_navigation.dart`, `lib/routes/routes.dart`, new `lib/features/pos/views/pos_returns_page.dart` + `viewmodels/pos_returns_viewmodel.dart`, `lib/data/services/pos_service.dart` (or a new `returns_service.dart`) + models, `material_release_page.dart`/viewmodel, `pos_shift_page.dart`/`shift_viewmodel.dart`, `test/core/sidebar_index_consistency_test.dart`.

1. **Returns tab** appended at index 6 (`Returns`, route `/pos/returns`, `AppRoutes.posReturns`). The order is append-only; don't renumber existing tabs. Flow: shift gate (same as the till: no open shift → message + "Go to Shifts") → search by transaction or receipt number (`?q=`) → load `returnable/` → choose qty per line (stepper capped at `remaining_qty`; lines with 0 remaining are disabled) → required reason → refund method (default Cash) → confirm dialog showing return value, debt reduced, and cash refund estimate → POST → **refund summary** card (return number, debt reduced, cash refund, new ledger balance). Map every server code to a clerk-readable message (`NO_OPEN_SHIFT`, `RETURN_QTY_EXCEEDED`, `RETURN_REASON_REQUIRED`, `RELEASE_NOT_RETURNABLE`, `RETURN_OF_RETURN`, `ORIGINAL_NOT_COMPLETED`, `UNLINKED_RETURN_FORBIDDEN`, 404 "not found or not yours").
2. **Release page:** on `NO_OPEN_SHIFT`, show "Open a shift before releasing materials" with a button to the Shifts tab. The token stays entered.
3. **Shift close:** if `held_cart_count > 0`, the close dialog warns "N held cart(s) remain — they stay held and can be resumed later" and still allows close. The Z-reading view shows the count.

**RED tests:** navigation consistency (7 items, index 6 → `/pos/returns`); returns viewmodel: search hit/miss, cap enforcement, reason required before submit, debt-first summary rendered from `refund_summary`, each error code → message; returns page widget flow (gate → search → submit → summary); release NO_OPEN_SHIFT message + Shifts button; close dialog shows the advisory when the count is > 0 and not when 0.

## Phase gate

1. Fresh `docker exec buildpro_backend python manage.py test --noinput`, `check`, `makemigrations --check --dry-run`; `flutter analyze`, `flutter test`.
2. **hygiene-reviewer** (`glm-5.3-flash`) on the full phase diff against this plan + decisions 03/05, security first.
3. **qa-tester** (`gpt-6-luna`) live:
   - (a) API probes for every RED case above on the running backend;
   - (b) **UI button audit**: run the Flutter web build and click every sidebar tab and every button on every page for each role (admin, manager, stocker, cashier), using a browser driver if Flutter web semantics allow, otherwise widget-level evidence. Report any control that does nothing, errors, or shows a parse/"could not be read" banner. Include the User Management list with a role-less account present;
   - (c) the cashier end-to-end flow: open shift → credit sale → partial return (debt-first) → release with/without shift → hold cart → close shift with the advisory.
4. Fix pass for Critical/Important, then MAP row 3 ✅, `ENDPOINTS.md`, a session note, and the AGENTS pointer.
