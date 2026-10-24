# ENDPOINTS.md — Flutter Feature → Backend Endpoint Mapping

This document maps every **frontend feature** (`flutter/lib/features/`) to the **backend endpoints** it consumes. The backend is organized by **domain** (Django apps), not by screen — this is intentional and follows Django best practice. Frontend "features" like `categories`, `products`, and `suppliers` are all one data domain (`apps/inventory`), while `admin`/`auth` are handled by `apps/users`, and `dashboard`/`reports` are aggregations served by existing apps. Use this table instead of restructuring the backend.

---

## 1. Base URL & Authentication

| Item | Value |
| --- | --- |
| Base URL (dev) | `http://10.0.2.2:8000` (Android emulator) / `http://127.0.0.1:8000` (web/desktop) — see `README.md` |
| API prefix | `/api/v1/` |
| Auth scheme | JWT Bearer (`rest_framework_simplejwt`) |
| Header | `Authorization: Bearer <access_token>` |
| Health check | `GET /api/health/` (public, no auth) |

### API conventions (agreed — do not break)

| Topic | Convention |
| --- | --- |
| Pagination | **Enabled** — DRF `PageNumberPagination` with `PAGE_SIZE = 50` (`config/settings.py`). Every list response is an envelope: `{ "count", "next", "previous", "results" }`. Read `results`, and page with `?page=N`. |
| Error format | DRF default: `{"detail": "..."}` for auth/permission errors; `{"field": ["msg"]}` for validation errors. Frontend should read `detail` or the first field error. |
| Idempotency | `POST /api/v1/transactions/` and `POST /api/v1/held-carts/{id}/complete/` accept an optional `Idempotency-Key` header (≤64 chars). A key is scoped **per cashier AND per endpoint/cart**: the same key reused on a different endpoint, or on a different held cart, is a **409**, never a replay. Same key + same scope + same body → **200** with the **original** transaction and no new writes; same key + different body **or different scope** → **409** `IDEMPOTENCY_KEY_REUSED`; empty or >64 chars → **400** `INVALID_IDEMPOTENCY_KEY`. Generate one key per checkout attempt and reuse it for every retry of that attempt — a new key rings a second sale. |
| 401 handling | Frontend retries once via `POST /auth/refresh/`; if that fails → logout to `/login`. |
| Null safety | Every account is created **with a role** (`group_name` required at registration), so `role` in user payloads is never `null`. |
| IDs | Integer PKs. Always serialize `id` in responses. |

---

## 2. Frontend Feature → Backend App (the big picture)

| Flutter feature folder | Backend app that serves it | Key endpoints |
| --- | --- | --- |
| `features/auth` | `apps/users` | `/api/v1/auth/*` |
| `features/admin` | `apps/users` | `/api/v1/users/*`, `/api/v1/audit-logs/*` |
| `features/categories` | `apps/inventory` | `/api/v1/categories/*`, `/api/v1/brands/*`, `/api/v1/uoms/*` |
| `features/products` | `apps/inventory` | `/api/v1/products/*`, `/api/v1/variants/*`, `/api/v1/variant-uoms/*` |
| `features/inventory` | `apps/inventory` | `/api/v1/purchase-orders/*`, `/api/v1/goods-receipts/*`, `/api/v1/batches/*`, `/api/v1/adjustments/*`, `/api/v1/alerts/*` |
| `features/suppliers` | `apps/inventory` | `/api/v1/suppliers/*` |
| `features/pos` | `apps/pos` | `/api/v1/transactions/*`, `/api/v1/customers/*`, `/api/v1/receipts/*`, `/api/v1/held-carts/*`, `/api/v1/shifts/*` |
| `features/sales` | `apps/pos` | `/api/v1/transactions/*`, `/api/v1/transactions/daily_report/` |
| `features/reports` | `apps/pos` + `apps/collectibles` | `/api/v1/transactions/daily_report/`, `/api/v1/ledgers/aging/` |
| *(collectibles / utang)* | `apps/collectibles` | `/api/v1/ledgers/*` |
| *(requisitions / material release)* | `apps/requisitions` | `/api/v1/requisitions/*`, `/api/v1/tokens/*` |

> **Note:** All ViewSets below are DRF `ModelViewSet`s registered with `DefaultRouter`, so every resource supports the standard REST operations unless marked read-only:
> `GET /<resource>/` (list), `GET /<resource>/{id}/` (retrieve), `POST /<resource>/` (create), `PUT /<resource>/{id}/`, `PATCH /<resource>/{id}/`, `DELETE /<resource>/{id}/`.

---

## 3. Full Endpoint Reference

### 3.1 Health — `config/urls.py`

| Method | Path | Purpose | Auth |
| --- | --- | --- | --- |
| GET | `/api/health/` | Connectivity check for Flutter | Public |

### 3.2 `apps/users` — auth, admin, audit

| Method | Path | Purpose | Auth |
| --- | --- | --- | --- |
| POST | `/api/v1/auth/login/` | Login (username or email + password) → JWT pair | Public |
| POST | `/api/v1/auth/refresh/` | Refresh access token | Public (refresh token in body) |
| POST | `/api/v1/auth/register/` | Create account — **`group_name` is required**, one of the six roles in `apps/users/permissions.py`: `Admin`, `System Administrator`, `Store Manager`, `Stock Manager`, `Cashier`, `Site Foreman` (`seed_demo` creates five, omitting `Admin`); guarantees every account has a non-null `role` | Admin **group** (`Admin` / `System Administrator`) or superuser |
| POST | `/api/v1/auth/logout/` | Logout (blacklists refresh token, writes audit log) | Authenticated |
| GET | `/api/v1/auth/me/` | Current user profile + roles | Authenticated |
| GET/POST/PUT/PATCH | `/api/v1/users/` | User CRUD (admin). Query param: `?search=<term>` matches **username**, full name, or email. **No `DELETE`** — the route answers **405**; accounts are deactivated (`is_active: false`), never deleted (audit rows will `PROTECT` their user). `is_staff` is **read-only over the API**: it only grants Django `/admin` login, never application authority | Admin **group** |
| GET | `/api/v1/users/stats/` | Account summary for dashboard cards: `{total, active, inactive, roles_assigned}` | Admin |
| POST | `/api/v1/users/{id}/assign_role/` | Assign Group — body: `{"group_name": "Cashier"}`; replaces the existing groups. Refused **400 `LAST_ADMIN`** when it would demote the last active admin | Admin **group** |
| POST | `/api/v1/users/{id}/remove_role/` | Remove Group — body: `{"group_name": "Cashier"}`. Refused **400 `LAST_ADMIN`** when it would demote the last active admin | Admin **group** |
| GET | `/api/v1/audit-logs/` | Immutable audit trail (read-only) | Admin **group** |

**Authority is the Admin group, not `is_staff`** (decision 04): `is_staff` keeps one meaning — it may log into Django's `/admin` site. API authority comes from `Admin` / `System Administrator` group membership; superusers bypass role checks.

**Last-admin guard:** any `PUT`/`PATCH` setting `is_active: false`, or any `assign_role` / `remove_role` that drops admin authority, is refused with `400 {"code": "LAST_ADMIN", "detail": "..."}` when that account is the last one that is active **and** is a superuser or a member of `Admin` / `System Administrator`. Deactivating a non-admin, or one of two admins, is allowed.

Roles map to Django's built-in `Group`/`Permission` (see `apps/users/models.py` ERD mapping: USER → `apps_users.User`, ROLE → `auth.Group`).

### 3.3 `apps/inventory` — products, catalog, purchasing, stock

| Method | Path | Purpose | Auth |
| --- | --- | --- | --- |
| GET/POST/PATCH/DELETE | `/api/v1/categories/` | Category CRUD | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/brands/` | Brand CRUD | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/uoms/` | Unit-of-measure CRUD | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/products/` | Product CRUD | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/variants/` | Product variant CRUD | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/variant-uoms/` | Variant selling-UOM CRUD | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/suppliers/` | Supplier CRUD | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/purchase-orders/` | Purchase order CRUD (nested items) | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/goods-receipts/` | Goods receipt CRUD. `POST` accepts `items: [{po_item, qty}]`; each entry adds to `POItem.received_qty` (capped at `ordered_qty`, else 400) **and** stores one `lines` row — the quantity that receipt delivered. Response carries `lines: [{id, po_item, variant, variant_name, qty}]` and read-only `processed_at` (null until processed). | Authenticated |
| POST | `/api/v1/goods-receipts/{id}/process/` | Turn **this receipt's own** lines into FIFO `InventoryBatch` rows and set `processed_at`. Batches use `line.qty`, `po_item.unit_cost`, `po_item.variant`. Receipts with no `lines` (legacy/`seed_demo`, which set `received_qty` directly) batch the delta vs. what the PO already put in stock, and answer `[]` when there is none. Re-processing → **400** `{"code": "RECEIPT_ALREADY_PROCESSED", "detail": "Goods receipt N was already processed."}`; the guard runs under a `select_for_update` lock on the receipt row, so concurrent calls cannot double-count. | Authenticated |
| GET | `/api/v1/batches/` | Inventory batches (stock on hand) — read-only | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/adjustments/` | Stock adjustment CRUD (`user` = request user, read-only). **Negative** `qty_adjusted` deducts through FIFO; **positive** reopens the **newest** batch of the variant, whatever its `current_qty` is (so a correction against an out-of-stock variant restocks it). Refusals are **400**: `qty_adjusted = 0` → `{"qty_adjusted": ["qty_adjusted must not be 0 …"]}`; positive with **no batch history** for the variant → `{"code": "NO_BATCH_HISTORY", "detail": "…", "variant_id": N}`; negative beyond stock on hand → `{"code": "INSUFFICIENT_STOCK", "detail": "…", "shortfall": "11.00", "variant_id": N}`. Row creation and the stock move are ONE `atomic` block, so a refused adjustment leaves **no** `StockAdjustment` row. | Authenticated |
| GET | `/api/v1/alerts/` | System alerts (low stock, expiring, etc.) | Authenticated (admin to write) |
| POST | `/api/v1/alerts/{id}/resolve/` | Resolve an alert | Admin |

### 3.4 `apps/pos` — checkout, customers, sales, receipts

| Method | Path | Purpose | Auth |
| --- | --- | --- | --- |
| GET/POST/PATCH/DELETE | `/api/v1/customers/` | Customer CRUD (walk-in, regular, contractor) | Authenticated |
| POST | `/api/v1/transactions/` | **Checkout** — body: `{customer, source, items[], payments[]}`; runs `process_sale` (server-priced lines, FIFO stock deduction on base units, payment allocation, OR generation, collectibles posting if underpaid). Honours `Idempotency-Key` (see *Idempotency* above). Failures are **400** `{code, detail}`: `INVALID_SALE` (line/qty/payment shape), `INSUFFICIENT_STOCK`, `CREDIT_LIMIT_EXCEEDED` (+ `limit`/`outstanding`/`shortfall`), `WALK_IN_CANNOT_OWE`, `NO_OPEN_SHIFT`; **409** `IDEMPOTENCY_KEY_REUSED` | Authenticated |
| GET | `/api/v1/transactions/` | Sales history (with items, payments, receipt) | Authenticated |
| GET | `/api/v1/transactions/daily_report/` | Today's totals: `{date, count, total_sales}` | Authenticated |
| GET | `/api/v1/payments/` | POS payments (read-only) | Authenticated |
| GET | `/api/v1/receipts/` | Official receipts (read-only) | Authenticated |
| GET | `/api/v1/held-carts/` | List held (parked) carts for the current cashier | Authenticated |
| POST | `/api/v1/held-carts/` | **Hold** — body: `{customer, notes, items[{variant_uom, qty, unit_price}]}`; parks the cart without touching stock | Authenticated |
| GET | `/api/v1/held-carts/{id}/` | Retrieve a single held cart with items | Authenticated |
| DELETE | `/api/v1/held-carts/{id}/` | **Void** a held cart — permanent delete, no stock change | Authenticated |
| POST | `/api/v1/held-carts/{id}/complete/` | **Complete** — body: `{customer?, payments[]}`; feeds items into `process_sale` (requires open shift) then deletes the cart. Honours `Idempotency-Key` (see *Idempotency* above): a retry after the cart was deleted returns the original sale with **200**, not 404 | Authenticated |
| POST | `/api/v1/shifts/open/` | **Open shift** — body: `{opening_float}`; one open shift per cashier enforced at DB level (400 `SHIFT_ALREADY_OPEN` if already open) | Authenticated |
| POST | `/api/v1/shifts/{id}/close/` | **Close shift** — body: `{closing_count}`; sets status=CLOSED, returns Z-reading (transaction_count, gross_sales, cash_sales, card_sales, gcash_sales, expected_drawer, variance) | Authenticated |
| GET | `/api/v1/shifts/current/` | Current cashier's open shift, or 404 `No open shift` | Authenticated |
| GET | `/api/v1/shifts/` | Shift list (own shifts for cashier, all for manager/admin) | Authenticated |

### 3.5 `apps/collectibles` — utang / accounts receivable

| Method | Path | Purpose | Auth |
| --- | --- | --- | --- |
| GET | `/api/v1/ledgers/` | Outstanding receivable entries (+ nested payments) | Authenticated |
| GET | `/api/v1/ledgers/aging/` | **Aging report** — overdue/open balances grouped by customer | Authenticated |
| POST/PATCH/DELETE | `/api/v1/ledgers/` | Ledger write operations | Admin (`IsAdminOrReadOnly`) |
| GET/POST/PATCH/DELETE | `/api/v1/ledger-payments/` | Collectible payments CRUD (posts against a ledger) | Authenticated |

> ℹ **Route note (fixed):** collectible payments were previously registered at `/api/v1/payments/`, which collided with the POS `payments` route and made them unreachable. They now live at **`/api/v1/ledger-payments/`**. Nested payments are still also visible inside `/api/v1/ledgers/` responses.

### 3.6 `apps/requisitions` — projects, material requests, tokens

| Method | Path | Purpose | Auth |
| --- | --- | --- | --- |
| GET/POST/PATCH/DELETE | `/api/v1/projects/` | Construction project CRUD | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/requisitions/` | Requisition CRUD (auto `req_number`, `requested_by` = current user) | Authenticated |
| POST | `/api/v1/requisitions/{id}/submit/` | DRAFT → SUBMITTED | Authenticated |
| POST | `/api/v1/requisitions/{id}/approve/` | SUBMITTED → APPROVED, generates `MaterialToken` (returns token UUID) | Authenticated |
| POST | `/api/v1/requisitions/{id}/reject/` | SUBMITTED → REJECTED | Authenticated |
| GET | `/api/v1/req-items/` | Requisition line items | Authenticated |
| GET | `/api/v1/tokens/` | Material tokens (read-only) | Authenticated |
| POST | `/api/v1/tokens/verify/` | Verify token — body: `{"token": "<uuid>"}` (UC-20) | Authenticated |
| POST | `/api/v1/tokens/release/` | **Material release at POS** — body: `{"token": "<uuid>"}`; FIFO-deducts stock, creates `SalesTransaction`, posts to `CollectibleLedger` (UC-21/22). Quantities are **base units** (`RequisitionItem.quantity`) and are priced from the variant's **factor-1** `VariantUOM` (`default_selling_price`), resolved for **every remaining line before the first write**. A line whose variant has no factor-1 selling unit → **400** `{"code": "NO_BASE_UOM", "detail": "…"}` with the token still unused and nothing written (no sale, receipt, ledger or stock move). Other token/state errors keep the plain `{"detail": "…"}` 400. | Cashier / Store Manager / Admin |

---

## 4. Typical Frontend Flows (which endpoints to call, in order)

| Flow | Endpoint sequence |
| --- | --- |
| Login | `POST /auth/login/` → store tokens → `GET /auth/me/` → route to role dashboard |
| Product catalog page | `GET /products/` (+ `GET /categories/`, `GET /brands/` for filters) |
| Receiving stock | `POST /purchase-orders/` → `POST /goods-receipts/` (carries the delivered `items` as `lines`) → `POST /goods-receipts/{id}/process/` (batches only that receipt's lines, once) |
| POS checkout | `GET /products/` → `POST /transactions/` (one call does stock deduction + payments + OR) |
| Utang monitoring | `GET /ledgers/` → `GET /ledgers/aging/` → `POST /ledger-payments/` |
| Foreman requisition | `POST /requisitions/` → `POST /requisitions/{id}/submit/` → approver: `POST /requisitions/{id}/approve/` → POS: `POST /tokens/verify/` → `POST /tokens/release/` |
| Daily dashboard/report | `GET /transactions/daily_report/` (optional `?date=YYYY-MM-DD`) + `GET /ledgers/aging/` + `GET /alerts/` |

## 4b. Reports Endpoints (`/api/v1/reports/` — Store Manager / Admin only)

| Method | Endpoint | Purpose |
| --- | --- | --- |
| GET | `/api/v1/reports/sales-summary/?from=YYYY-MM-DD&to=YYYY-MM-DD` | Daily sales totals (count, gross, VAT, discounts) + range totals. Defaults to last 30 days. |
| GET | `/api/v1/reports/inventory-valuation/` | Stock value at cost & retail, grouped by category + grand totals. |
| GET | `/api/v1/reports/stock-movements/?from=&to=` | Stock IN (goods receipts/day) vs OUT (adjustments by type). |
| GET | `/api/v1/reports/requisition-history/?status=&from=&to=` | Counts per status + filtered requisition list (max 200). `status` must be a valid Requisition status (DRAFT, SUBMITTED, APPROVED, REJECTED, PARTIAL, RELEASED, CANCELLED). |


## 5. Gaps / TODOs observed while writing this doc (backend)

1. ~~**Route collision** on `/api/v1/payments/`~~ — **FIXED**: collectible payments moved to `/api/v1/ledger-payments/`.
2. ~~**Role-level permissions not yet enforced per endpoint**~~ — **FIXED**: role permissions enforced via `apps/users/permissions.py`. Matrix:

   | Endpoint group | Write access | Read access |
   | --- | --- | --- |
   | Auth (`login/`, `verify/`, `refresh/`) | Public / Authenticated | — |
   | Users CRUD, roles, audit logs, register | Admin **group** (`IsAdminRole`) | Admin **group** |
   | Inventory catalog & stock (products, categories, brands, UOMs, suppliers, POs, goods receipts + `process`, stock adjustments) | Stock Manager / Store Manager / Admin | Any authenticated |
   | System alerts (incl. `resolve`) | Admin | Any authenticated |
   | POS (transactions, customers) | Cashier / Store Manager / Admin | Any authenticated |
   | Payments & official receipts | read-only | Any authenticated |
   | Collectible ledgers | Admin | Any authenticated |
   | Collectible payments (`/ledger-payments/`) | Cashier / Store Manager / Admin | Any authenticated |
   | Projects, requisitions, requisition items | Site Foreman / Store Manager / Admin | Any authenticated |
   | Requisition `submit` | Site Foreman / Store Manager / Admin | — |
   | Requisition `approve` / `reject` | Store Manager / Admin | — |
   | Token `verify` | Any authenticated | — |
   | Token `release` | Cashier / Store Manager / Admin | — |

   Superusers bypass all role checks. Frontend role route guards (`/admin/*` etc.) are now backed by matching API enforcement. `is_staff` is **not** API authority (decision 04); `/users/` has no `DELETE` (405) and `is_staff` is read-only via the API — see §3.2.
3. ~~**`tests.py` are still empty stubs**~~ — **FIXED**: 546 lines of real tests across all 5 apps (`users` 140, `requisitions` 128, `inventory` 121, `pos` 95, `collectibles` 62). Run with `docker compose exec backend python manage.py test`.
4. ~~No dedicated `reports` aggregation endpoints yet~~ — **FIXED**: new read-only `apps/reports` (§4b) with `sales-summary`, `inventory-valuation`, `stock-movements`, `requisition-history`; `daily_report` now accepts `?date=`.

