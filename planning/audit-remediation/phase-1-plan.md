# Phase 1 Plan — Money & Stock Integrity

**Spec:** [MAP](./MAP.md) decisions [UOM and price authority](./decisions/01-uom-and-price-authority.md), [Credit limit](./decisions/08-credit-limit.md), [Integrity mechanics](./decisions/09-integrity-mechanics.md).
**Branch:** `feature/backend-integration`. **BASE:** `5c7fce7`. **Baseline:** backend 107/107 OK.

## Global constraints

- Backend tests: `docker exec buildpro_backend python manage.py test <label>`; full suite `docker exec buildpro_backend python manage.py test`. Migrations: `docker exec buildpro_backend python manage.py makemigrations <app> -n <name>` (the container bind-mounts `backend_django/`, so files appear in the repo).
- `POSTestBase` (`apps/pos/tests.py:41`) extends Django `TestCase`: nested JSON writes need `content_type='application/json'`. Its fixture VariantUOM has CF=1, price 10; stock 5@40 + 5@60.
- **RED first:** write the test, run it, see it FAIL for the right reason (assertion, not import/syntax error), then implement. Paste RED and GREEN output in the report.
- Business-rule errors return HTTP 400 `{code, detail, ...}` through `apps/pos/exceptions.py::handler` (409 for idempotency conflicts). Never a 500.
- Existing tests that assert old (unsafe) behavior — e.g. client-chosen `unit_price` — are updated to the new rule; list each changed assertion in the report.
- No CPMS, no Flutter in Tasks 1–5. Do not touch `temp/`.
- Commit per task: `fix(pos): …` / `fix(inventory): …` / `feat(pos): …` with tests in the same commit.

## Task 1 — Sale validation, server price, UOM conversion

**Files:** `apps/pos/services.py` (`process_sale`, `process_return`), `apps/pos/views.py` (`SalesTransactionViewSet.create`, `HeldCartViewSet.complete`), `apps/pos/exceptions.py`, new `apps/pos/tests_sale_integrity.py`.

1. Add `InvalidSale(ValueError)` with `code='INVALID_SALE'` (+ handler branch → 400 `{code, detail}`).
2. In `process_sale`, before any write, validate `items_data`: list, 1..200 lines; each `variant_id` resolves to an existing `VariantUOM` whose variant and product are `is_active` (no fallback to ProductVariant id — remove the ambiguous resolution); `qty` parses as Decimal, finite, > 0. Validate `payments_data`: list; each `method` in `Payment.Method`; `amount_tendered` Decimal ≥ 0. Bad → `InvalidSale`.
3. Server price: `unit_price = vuom.default_selling_price`; ignore any client `unit_price`.
4. Conversion: `base_qty = qty * vuom.conversion_factor`; `allocate_fifo(variant_id=vuom.variant_id, qty_needed=base_qty)`. `SalesItem.qty` stays selling qty.
5. `process_return`: same validation of `variant_id`/qty; restock `qty * conversion_factor` base units; price = the original sale's `SalesItem.unit_price` for that VariantUOM when linked (InvalidSale/ReturnError if the UOM was not on the original), else `default_selling_price`. Ignore client `unit_price`.
6. `HeldCartViewSet.complete` passes through `process_sale` (gets validation + server price automatically); held price is no longer authoritative — note in report.

**RED tests (tests_sale_integrity.py):** CF=12 VariantUOM sale of qty 1 deducts 12 base units; forged `unit_price 0.01` records 10.00 and grand_total 10.00; empty items → 400 INVALID_SALE, no transaction/receipt rows; qty 0 / -1 / "abc" → 400; unknown variant_id → 400; inactive variant → 400; bogus payment method → 400; negative amount → 400; return of 1 box (CF 12) linked restocks 12 and refunds original line price, forged return price ignored; held-cart complete with tampered held `unit_price` records server price.

## Task 2 — Credit limit hard block

**Files:** `apps/pos/models.py` (`Customer.total_credit_limit`), migration, `apps/pos/services.py`, `apps/pos/exceptions.py`, `apps/pos/management/commands/seed_demo.py` (find actual path), tests in `tests_sale_integrity.py`.

1. `total_credit_limit` → `null=True, blank=True, default=None`. Migration + data migration setting existing `0` → `NULL` (null = unlimited, 0 = no credit).
2. `CreditLimitExceeded(Exception)` code `CREDIT_LIMIT_EXCEEDED`, carries `limit`, `outstanding`, `shortfall`; handler → 400 with those as strings.
3. In `process_sale` after WALK_IN check: if limit is not None, `outstanding = sum(balance_due)` of that customer's ledgers with status OPEN/PARTIAL/OVERDUE (lock with `select_for_update` on the customer row first to serialize concurrent credit); if `outstanding + shortfall > limit` → raise (rollback).
4. Seed: Maria Santos gets explicit limit `10000`.

**RED tests:** limit 500, outstanding 400, new shortfall 200 → 400, no txn/ledger/stock change; null limit → ledger created; limit 0 → any shortfall 400; exactly-at-limit allowed; fully paid sale with limit 0 allowed; walk-in rule unchanged.

## Task 3 — Collision-safe numbering + idempotent checkout

**Files:** `apps/pos/models.py` (new `DocumentCounter`; `SalesTransaction.idempotency_key`, `request_hash`), migration, `apps/pos/services.py`, `apps/pos/views.py`, tests `apps/pos/tests_idempotency.py`.

1. `DocumentCounter(prefix CharField, day DateField, last IntegerField)` unique `(prefix, day)`. `next_number(prefix)` does `get_or_create` then `select_for_update` and increments inside the caller's atomic block. `generate_transaction_no` / `generate_or_number` use it (format unchanged: `TRX-YYYYMMDD-0001`, `OR-…`). Seed counter from existing max on first use of a day so live data does not collide.
2. `SalesTransaction.idempotency_key = CharField(max_length=64, null=True, blank=True)`, `request_hash = CharField(max_length=64, blank=True, default='')`; `UniqueConstraint(fields=['cashier','idempotency_key'], condition=Q(idempotency_key__isnull=False))`.
3. `POST /transactions/` and `POST /held-carts/{id}/complete/` read header `Idempotency-Key` (optional; ≤64 chars, else 400 INVALID_IDEMPOTENCY_KEY). Hash = sha256 of canonical JSON of the request body. If a txn exists for (user, key): same hash → return it with **200** (not 201) and no new writes; different hash → **409** `{code: IDEMPOTENCY_KEY_REUSED}`. Race: catch `IntegrityError` on create, then re-read and apply the same rule.
4. Held-cart replay after the cart was deleted must return the original transaction, not 404 — check the key **before** `get_object()`.

**RED tests:** same key twice → one transaction, one receipt, stock deducted once, second response 200 same id; same key different body → 409; different cashiers same key → two transactions; no key → behaves as today; numbering: pre-insert a transaction `TRX-<today>-0007` without a counter → next sale gets `-0008` (no IntegrityError); 2 sequential sales get consecutive numbers. (True concurrency is exercised by qa-tester live.)

## Task 4 — Goods receipts process their own lines

**Files:** `apps/inventory/models.py` (new `GoodsReceiptItem`, `GoodsReceipt.processed_at`), migration, `apps/inventory/views.py` (`GoodsReceiptViewSet.create/process`), `apps/inventory/services.py` (`process_goods_receipt`), serializer exposes `items` read-only + `processed_at`, tests in `apps/inventory/tests_goods_receipt_api.py`.

1. `GoodsReceiptItem(receipt FK related_name='lines' CASCADE, po_item FK PROTECT, qty Decimal >0)`. `create` writes one line per delivered entry (qty > 0) alongside the cumulative `POItem.received_qty` update (keep the over-order cap). Lock each `POItem` with `select_for_update` inside the atomic block when accumulating.
2. `process_goods_receipt`: inside atomic, `select_for_update` the receipt; if `processed_at` set → raise `ReceiptAlreadyProcessed` (400). If receipt has lines → one batch per line with `line.qty`. If no lines (legacy) → per PO item, `delta = received_qty − sum(initial_qty of batches on this PO for that variant)`; batch only `delta > 0`. Set `processed_at`. PO status logic unchanged. Remove the view-level `batches.exists()` guard in favour of the service guard (same 400 message).

**RED tests:** receipt A qty 5 processed, receipt B qty 2 processed → total batch qty 7 (today 12); processing the same receipt twice → second 400 and still one batch set; legacy receipt (no lines, received_qty set directly, as in POSTestBase) still produces correct batches; zero-qty entries create no line.

## Task 5 — Adjustments and release preconditions

**Files:** `apps/inventory/services.py` (`apply_stock_adjustment`), `apps/inventory/views.py` (adjustment create error mapping), `apps/requisitions/services.py` (`release_materials`), tests in `apps/inventory/tests.py` and `apps/requisitions/tests.py`.

1. Positive adjustment with no active batch: reopen the newest batch for the variant (any `current_qty`, ordered `-receipt__receive_date, -id`); if the variant has never had a batch → raise `ValueError`-subclass `NoBatchHistory` code `NO_BATCH_HISTORY` → 400 and the `StockAdjustment` row is not saved (wrap create + apply in one atomic). Remove the duplicated `allocate_fifo` retry in the negative branch.
2. `release_materials`: before any write, for every remaining item resolve the factor-1 VariantUOM; if missing → raise `ValueError('NO_BASE_UOM …')` mapped to 400 `{code:'NO_BASE_UOM'}` by the existing release view error path (inspect it); nothing written, token stays unused.

**RED tests:** positive +5 on a variant whose only batch is at 0 → stock 5; positive on variant with zero batches → 400 and no adjustment row; release with an item lacking CF=1 VariantUOM → 400 NO_BASE_UOM, token `is_used=False`, no transaction, stock unchanged.

## Task 6 — Flutter client contract

**Files:** `flutter/lib/core/network/api_client.dart` (`post` gains optional `headers`), `flutter/lib/data/services/pos_service.dart`, `flutter/lib/data/services/held_cart_service.dart`, `flutter/lib/features/pos/viewmodels/pos_transaction_viewmodel.dart`, tests under `flutter/test/`.

1. `ApiClient.post(path, {data, Map<String,String>? headers})`.
2. Checkout and held-cart complete send `Idempotency-Key`: a UUID-v4-like random string created when the cashier starts a payment attempt and **reused** for retries of that same attempt; cleared only on success or when the cart changes. (No new package; use `Random.secure()`.)
3. Map new error codes to cashier messages: `INVALID_SALE` (detail), `CREDIT_LIMIT_EXCEEDED` ("Credit limit exceeded: outstanding X + this sale Y > limit Z"), `IDEMPOTENCY_KEY_REUSED`, `NO_BASE_UOM`.
4. Displayed totals stay client-computed for preview; receipt screen shows **server** totals from the response (verify current code does; fix if not).

**RED tests:** service test asserts header present and stable across a retry; viewmodel test: failed submit then retry reuses key, success then new sale uses new key; error mapping tests for the new codes. Gate: `flutter test` all green + `flutter analyze` clean.

## Phase gate

Backend full suite green, `manage.py check` clean, `makemigrations --check --dry-run` clean; Flutter full suite + analyze clean; hygiene-reviewer pass on `5c7fce7..HEAD`; qa-tester live probe of every abuse case above against the running backend (incl. two truly concurrent sales and same-key replay).
