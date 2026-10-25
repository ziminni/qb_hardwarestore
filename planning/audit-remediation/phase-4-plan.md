# Phase 4 Plan — Stock Manager

**Spec:** [MAP](./MAP.md) row 4 (no new decision file; follows audit findings) plus **user decision 2026-10-25:** *a new product's first stock arrives through a purchase order the Stock Manager creates and then receives. "Add product" creates the catalog item only.* **(R)** marks research findings, ledgered as rulings.
**Branch:** `feature/backend-integration`. **BASE:** `85413d6`. **Baseline:** backend 383/383 (`manage.py test --noinput`), flutter 694/694.

## Global constraints

- Same rules as Phases 1–3: tests run in docker with `--noinput`, `content_type='application/json'` for nested writes, RED first (an assertion failure, not an import error), one commit per task with its tests, no CPMS, no `temp/`. Stage explicit paths only.
- Phase 2/3 security stays intact. Catalog/purchasing **writes** = `IsInventoryRole` (Stock Manager + Admin, superuser). Reads stay authenticated. Every refusal is a stable `{code, detail}` 4xx, never a 500.
- Every catalog/purchasing write that changes money or stock meaning (create/edit/archive product, variant, selling unit price, category, supplier, PO create/place/cancel) writes **one** `AuditLog` row (`CREATE`/`UPDATE`) inside its transaction. Descriptions name the object, never secrets.
- **No dead controls** (guard test stays green). **No local-only mutation:** every Stock Manager action must reach the server and survive a reload. Remove `InventoryViewmodel` mock mutation paths (`addProduct`, `updateProduct`, `updateCategory`, `archiveCategory`, `sellStock`, `_deductFifo` if unused) once replaced.
- `ENDPOINTS.md` is the single home for the API contract.

## Task 1 — Catalog write hardening (backend)

**Files:** `apps/inventory/{models,serializers,views}.py`, migration, new `apps/inventory/tests_catalog_writes.py`.

1. **No deletes (R):** categories, brands, uoms, products, variants, variant-uoms, suppliers and purchase-orders lose `DELETE` (405). Everything is referenced by sales/batches through `PROTECT`, so today a delete is a 500 or orphans history. Use archive instead.
2. **Category archive (R):** add `Category.is_active` (default True; migration). Products in an archived category stay sellable. The UI hides the category from the "new product" picker.
3. **Selling-unit integrity (R):** `VariantUOM.conversion_factor > 0` and `default_selling_price >= 0` → 400 `INVALID_SELLING_UNIT`. At most one factor-1 unit per variant (400 `DUPLICATE_BASE_UNIT`). `conversion_factor`, `uom` and `variant` are **immutable once any SalesItem/HeldCartItem references the unit** (400 `SELLING_UNIT_IN_USE`): changing them would corrupt return caps and restock. Price stays editable.
4. **Variant integrity:** `min_stock_threshold >= 0`, `max_stock_level >= 0` → 400 `INVALID_VARIANT`. `product`/`base_uom` immutable after creation.
5. **Audit:** CREATE/UPDATE rows for product, variant, selling unit (price changes name old → new), category, supplier.

**RED tests:** stocker DELETE product/category/variant/vuom/supplier/PO → 405 and the row exists. Cashier/foreman POST product → 403. Factor 0 / negative price → 400. A second factor-1 unit → 400. PATCH factor of a sold unit → 400 and unchanged, PATCH its price → 200 + audit row old→new. Category archive → `is_active=false`, its products still sell. One audit row per write, none per refusal.

## Task 2 — Purchase orders: create, place, cancel (backend)

**Files:** `apps/inventory/{serializers,views,services}.py`, `apps/inventory/tests_purchase_orders.py`.

1. `POST /purchase-orders/` with nested `items: [{variant, ordered_qty, unit_cost}]` creates the PO (DRAFT) and its POItems atomically. `created_by` = request user (read-only). Validation: supplier active (400 `SUPPLIER_INACTIVE`), ≥1 line, `ordered_qty > 0`, `unit_cost >= 0`, variant active, no duplicate variant on one PO → 400 `INVALID_PO`.
2. `status` read-only on the serializer. Transitions are actions only: `POST /purchase-orders/{id}/place/` DRAFT→ORDERED; `POST /purchase-orders/{id}/cancel/` DRAFT/ORDERED with nothing received → CANCELLED, else 400 `PO_HAS_RECEIPTS`. Wrong state → 400 `INVALID_PO_STATE`. Edit (PATCH notes/expected_delivery/items) only while DRAFT → else 400 `PO_LOCKED`. Items can be replaced wholesale while DRAFT.
3. Receiving (existing goods-receipt create/process) accepts only ORDERED/PARTIAL POs → a DRAFT PO is 400 `PO_NOT_ORDERED`. Existing COMPLETE/CANCELLED refusals keep their behaviour, now with stable codes.
4. Audit: PO CREATE, place/cancel UPDATE (and RECEIPT as today).

**RED tests:** create with lines → 201, DRAFT, lines saved, `created_by` is the caller even if the body says otherwise. Inactive supplier / zero qty / negative cost / duplicate variant / empty items → 400 and no rows. PATCH `status` → ignored. Place → ORDERED. Receive a DRAFT → 400. Cancel ORDERED-unreceived → CANCELLED. Cancel PARTIAL → 400. Cashier create → 403. Full flow: create → place → receive 5 of 10 (PARTIAL) → receive 5 (COMPLETE) → stock +10 at the PO cost.

## Task 3 — Low-stock alerts on every stock-out + dedup (backend)

**Files:** `apps/inventory/services.py` (`_check_low_stock`), `apps/pos/services.py` (`process_sale`), `apps/requisitions/services.py` (`release_materials`), tests `apps/inventory/tests_alert_triggers.py`.

1. Call the check once per affected variant after FIFO deduction in `process_sale` and `release_materials`, inside their transactions. A held-cart complete goes through `process_sale`, so it is covered.
2. **Dedup:** don't create an alert when an **unresolved** alert of the same type already exists for the variant. Escalation: going from LOW to OUT creates an OUT_OF_STOCK alert, while the open LOW alert stays as is.
3. Lock the variant row (`select_for_update`) before the existence check, so concurrent sales can't create duplicates.
4. A return or receipt that restores stock does not auto-resolve alerts; resolving stays manual (decision 06).

**RED tests:** a sale taking stock below threshold → one LOW_STOCK alert; a second sale still below → still one; a sale to 0 → one OUT_OF_STOCK added; a release below threshold → alert; after resolve, the next low sale → a new alert; threshold 0 → no LOW alert; a sale refused for insufficient stock → no alert.

## Task 4 — Stock Manager screens live (Flutter)

**Files:** `lib/features/products/**`, `lib/features/categories/**`, `lib/features/suppliers/**`, `lib/features/inventory/views/{inventory_low_stock_page,inventory_receiving_page}.dart`, `lib/features/inventory/viewmodels/inventory_viewmodel.dart`, services/repositories under `lib/data/**`, tests.

1. **Products:** Add product = server create chain (product → variant → factor-1 selling unit with price, optional barcode) through one repository call. A partial failure doesn't leave an orphan the UI hides: report exactly which step failed and reload. **Remove the opening-stock fields** and replace them with the hint "Stock arrives through a purchase order → Receiving". Edit (name, description, category, brand, threshold, selling price) and Archive/Restore use PATCH. All reload from the server; no synthetic IDs. Each server code gets a clerk-readable message.
2. **Categories:** live list/create/rename/archive/restore (`categories_page` currently snackbars "updated in mock data").
3. **Suppliers:** create/edit/activate-deactivate via the server. Delete the session-local `_activeOverrides`.
4. **Purchase orders:** a "New purchase order" screen/dialog (supplier, lines of variant + qty + unit cost, expected delivery, notes) → Save draft / Place order. The PO list shows status, with Place and Cancel actions where valid and a read-only View. The Receiving tab lists ORDERED/PARTIAL POs only.
5. **Low stock:** the "Reorder" button (today a "Future Purchasing connection" placeholder dialog) opens New purchase order prefilled with that variant (qty = max_stock_level − on hand when > 0, else threshold). A **Resolve** action on each alert calls `POST /alerts/{id}/resolve/` and shows resolver + time. Only the inventory role sees Resolve.
6. **Goods-receipt history:** Receiving gets a "Received deliveries" list (`GET /goods-receipts/`: date, PO, DR no., received by, lines + qty, processed) with a View sheet.

**RED tests:** add-product chain posts the three bodies in order with the server ids threaded, and a reload shows the product. A failure at step 2 surfaces "variant could not be created" and reloads. Edit price → PATCH variant-uom. Archive → PATCH `is_active=false`. Categories create/archive hit the server, with no "mock data" text left anywhere (grep test). Supplier toggle → PATCH, and the state survives a reload. PO create body shape, place/cancel calls, Receiving filter. Reorder prefill. Resolve call + resolver shown + hidden for non-inventory roles. Receipt history list + sheet. Route-wiring tests for any new route through the real router (provider placement mirrors `main.dart`).

## Phase gate

1. Fresh backend tests (`--noinput`), `check`, `makemigrations --check --dry-run`, `migrate` on the dev DB; `flutter analyze`, `flutter test`.
2. **hygiene-reviewer** ×2 (backend half, Flutter half), security first.
3. **qa-tester** API probes for every RED case.
4. **qa-tester browser E2E** (Flutter web build, 1920×1080) as the Stock Manager: add a product → it appears after reload. Create a PO for it → place → receive part → receive the rest → stock shows. A cashier sells it below threshold → a low-stock alert appears (Notifications + Low stock) → the stocker resolves it. Edit the price → the till charges the new price. Archive and restore. Categories + supplier toggle survive a reload. Reorder prefills a PO. Receipt history lists the deliveries. Then **click every control on every tab for all 4 roles** (dead-button audit) and run one cashier sale as a regression.
5. Fix pass, then MAP row 4 ✅, `ENDPOINTS.md`, a session note, and the AGENTS pointer.
