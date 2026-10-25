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
| Idempotency | `POST /api/v1/transactions/` and `POST /api/v1/held-carts/{id}/complete/` accept an optional `Idempotency-Key` header (≤64 chars). A key is scoped **per cashier AND per endpoint/cart**: the same key reused on a different endpoint, or on a different held cart, is a **409**, never a replay. Same key + same scope + same body → **200** with the **original** transaction and no new writes; same key + different body **or different scope** → **409** `IDEMPOTENCY_KEY_REUSED`; empty or >64 chars → **400** `INVALID_IDEMPOTENCY_KEY`. Generate one key per checkout attempt and reuse it for every retry of that attempt — a new key rings a second sale. **Browsers:** `Idempotency-Key` is a custom header, so it must be listed in `CORS_ALLOW_HEADERS` (`config/settings.py`) or the web preflight fails and the POST never leaves the browser. |
| 401 handling | Frontend retries once via `POST /auth/refresh/`; if that fails → logout to `/login`. |
| Null safety | Registration **requires** a role (`group_name`), but `role` in a user payload **can be `null`**: `createsuperuser`, an account created in the Django admin, or one whose group was removed has no group. `GET /users/` and `GET /auth/me/` both carry that null, so clients treat role as nullable — Flutter `User.role` is `Role?` and renders "No role" (Phase 3 Task 0). `id`, `username`, `email` and `full_name` are still always present, and a `role` that is present but **not** an object is still a contract break. |
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
| POST | `/api/v1/auth/login/` | Login (username or email + password) → JWT pair. **Lockout:** 5 failures for one `(identifier, client address)` pair inside 15 minutes → **429** `{"code": "LOGIN_LOCKED", "detail": "Too many failed sign-in attempts. Try again in N minutes.", "retry_after": <seconds>}` — answered **without checking the password**. A success clears the counter; the counter is kept in the cache (`apps/users/lockout.py`), so it expires by itself and is **per worker process** until production points `CACHES` at a shared backend. Every **checked** failure writes a `LOGIN_FAILED` audit row (a locked attempt is refused unread and writes none) (actor = the matched account, else `username_snapshot` = attempted identifier); the body for an unknown user and a wrong password is identical, and a disabled account's refusal counts as a failure | Public |
| POST | `/api/v1/auth/refresh/` | Refresh access token. Rotation is on: the response carries a **new** refresh token, and the token just used is blacklisted — **reusing a rotated refresh token → 401**. A **deactivated** account's refresh token → **401** (`no_active_account`) | Public (refresh token in body) |
| POST | `/api/v1/auth/register/` | Create account — **`group_name` is required**, one of the six roles in `apps/users/permissions.py`: `Admin`, `System Administrator`, `Store Manager`, `Stock Manager`, `Cashier`, `Site Foreman` (`seed_demo` creates five, omitting `Admin`); guarantees every account has a non-null `role` | Admin **group** (`Admin` / `System Administrator`) or superuser |
| POST | `/api/v1/auth/logout/` | Logout. Optional body `{"refresh": "<token>"}`: when it parses **and** belongs to the caller, it is blacklisted (that token then fails `/auth/refresh/` with **401**). A garbage, expired, already-rotated or foreign token is ignored. **Always 204** — local sign-out never fails; a `LOGOUT` audit row is written either way | Authenticated |
| GET | `/api/v1/auth/me/` | Current user profile + roles | Authenticated |
| GET/POST/PUT/PATCH | `/api/v1/users/` | User CRUD (admin). Query param: `?search=<term>` matches **username**, full name, or email. **No `DELETE`** — the route answers **405**; accounts are deactivated (`is_active: false`), never deleted (audit rows will `PROTECT` their user). `is_staff` is **read-only over the API**: it only grants Django `/admin` login, never application authority | Admin **group** |
| GET | `/api/v1/users/stats/` | Account summary for dashboard cards: `{total, active, inactive, roles_assigned}` | Admin |
| POST | `/api/v1/users/{id}/assign_role/` | Assign Group — body: `{"group_name": "Cashier"}`; replaces the existing groups. Refused **400 `LAST_ADMIN`** when it would demote the last active admin | Admin **group** |
| POST | `/api/v1/users/{id}/remove_role/` | Remove Group — body: `{"group_name": "Cashier"}`. Refused **400 `LAST_ADMIN`** when it would demote the last active admin | Admin **group** |
| GET | `/api/v1/audit-logs/` | Audit trail — **append-only** and read-only over HTTP (no POST/PUT/PATCH/DELETE for any role, Django admin included). Row: `{id, user, user_email, username_snapshot, action_type, description, ip_address, timestamp}`; `user_email` is `null` when the actor is unknown. Action types: `LOGIN`, `LOGIN_FAILED`, `LOGOUT`, `CREATE`, `UPDATE`, `DELETE`, `USER_DEACTIVATE`, `ROLE_CHANGE`, `SALE`, `RETURN`, `RELEASE`, `CART_VOID`, `STOCK_ADJUST`, `RECEIPT`, `PAYMENT`, `REQ_APPROVE`, `REQ_REJECT`, `ALERT_RESOLVE`, `SHIFT_OPEN`, `SHIFT_CLOSE`. Every business event writes **exactly one** row inside the same transaction as the event (a refused or replayed event writes none); descriptions name the **document number** (`TRX-…`, `REQ-…`, cart/adjustment/alert id) and never a credential (no password, JWT or material-token UUID). `ip_address` comes from `REMOTE_ADDR` only. `username_snapshot` is the actor's name copied onto the row, so the trail still reads after the account is deactivated; rows cannot be edited or deleted (`PROTECT` on `user` as well) | Admin **group** |

**Authority is the Admin group, not `is_staff`** (decision 04): `is_staff` keeps one meaning — it may log into Django's `/admin` site. API authority comes from `Admin` / `System Administrator` group membership; superusers bypass role checks.

**Last-admin guard:** any `PUT`/`PATCH` setting `is_active: false`, or any `assign_role` / `remove_role` that drops admin authority, is refused with `400 {"code": "LAST_ADMIN", "detail": "..."}` when that account is the last one that is active **and** is a superuser or a member of `Admin` / `System Administrator`. Deactivating a non-admin, or one of two admins, is allowed.

Roles map to Django's built-in `Group`/`Permission` (see `apps/users/models.py` ERD mapping: USER → `apps_users.User`, ROLE → `auth.Group`).

### 3.3 `apps/inventory` — products, catalog, purchasing, stock

| Method | Path | Purpose | Auth |
| --- | --- | --- | --- |
| GET/POST/PATCH | `/api/v1/categories/` | Category list/create/edit. **No `DELETE`** → **405** for every role, Admin included (products are `PROTECT`-referenced, so a delete was a 500). Archive instead: `PATCH {"is_active": false}` hides the category from the "new product" picker while **its products stay sellable** (the till prices a line from the selling unit, never from the category). `is_active` defaults to `true`; restore with `PATCH {"is_active": true}`. One `CREATE`/`UPDATE` `AuditLog` row per write. | read: any authenticated · write: Stock Manager / Store Manager / Admin |
| GET/POST/PATCH | `/api/v1/brands/` | Brand list/create/edit. **No `DELETE`** → **405** (products are `PROTECT`-referenced). Not audited (a brand carries no money or stock meaning). | read: any authenticated · write: Stock Manager / Store Manager / Admin |
| GET/POST/PATCH | `/api/v1/uoms/` | Unit-of-measure list/create/edit. **No `DELETE`** → **405** (variants and selling units are `PROTECT`-referenced). Not audited. | read: any authenticated · write: Stock Manager / Store Manager / Admin |
| GET/POST/PATCH | `/api/v1/products/` | Product list/create/edit, `variants[]` nested read-only. **No `DELETE`** → **405** (variants are `CASCADE`, batches `PROTECT`): archive with `PATCH {"is_active": false}`. One `CREATE`/`UPDATE` `AuditLog` row per write, naming the product. | read: any authenticated · write: Stock Manager / Store Manager / Admin |
| GET/POST/PATCH | `/api/v1/variants/` | Product variant list/create/edit, `selling_uoms[]` nested read-only. **No `DELETE`** → **405** (batches and sale deductions `PROTECT`). `product` and `base_uom` are **set at creation**: changing either → **400** `{"code": "INVALID_VARIANT", "detail": "…"}`, and so does a negative `min_stock_threshold` / `max_stock_level`. Archive via `is_active`. One audit row per write. | read: any authenticated · write: Stock Manager / Store Manager / Admin |
| GET/POST/PATCH | `/api/v1/variant-uoms/` | Selling-unit list/create/edit (`uom_code`/`uom_name` read-only). **No `DELETE`** → **405** (sale lines `PROTECT`). Refusals are **400**: `conversion_factor <= 0` or `default_selling_price < 0` → `{"code": "INVALID_SELLING_UNIT", "detail": "…"}`; a **second** factor-1 unit on one variant → `{"code": "DUPLICATE_BASE_UNIT", "detail": "…"}`; changing `variant`, `uom` or `conversion_factor` **once the unit has been sold or is in a held cart** → `{"code": "SELLING_UNIT_IN_USE", "detail": "…"}` with nothing written. **The price stays editable** (a sale line keeps its own `unit_price`), and a price change writes one `UPDATE` audit row reading `price 10.00 -> 12.50`. | read: any authenticated · write: Stock Manager / Store Manager / Admin |
| GET/POST/PATCH | `/api/v1/suppliers/` | Supplier list/create/edit. **No `DELETE`** → **405** (purchase orders are `PROTECT`-referenced): deactivate with `PATCH {"is_active": false}`. One audit row per write. | read: any authenticated · write: Stock Manager / Store Manager / Admin |
| GET/POST/PATCH | `/api/v1/purchase-orders/` | Purchase order list/create/edit (line items are nested on the serializer — there is no `/po-items/` endpoint). **No `DELETE`** → **405** (receipts are `PROTECT`-referenced; cancel instead, see *Purchasing* below). | read: any authenticated · write: Stock Manager / Store Manager / Admin |
| GET/POST/PATCH/DELETE | `/api/v1/goods-receipts/` | Goods receipt CRUD. `POST` accepts `items: [{po_item, qty}]`; each entry adds to `POItem.received_qty` (capped at `ordered_qty`, else 400) **and** stores one `lines` row — the quantity that receipt delivered. Response carries `lines: [{id, po_item, variant, variant_name, qty}]` and read-only `processed_at` (null until processed). | Authenticated |
| POST | `/api/v1/goods-receipts/{id}/process/` | Turn **this receipt's own** lines into FIFO `InventoryBatch` rows and set `processed_at`. Batches use `line.qty`, `po_item.unit_cost`, `po_item.variant`. Receipts with no `lines` (legacy/`seed_demo`, which set `received_qty` directly) batch the delta vs. what the PO already put in stock, and answer `[]` when there is none. Re-processing → **400** `{"code": "RECEIPT_ALREADY_PROCESSED", "detail": "Goods receipt N was already processed."}`; the guard runs under a `select_for_update` lock on the receipt row, so concurrent calls cannot double-count. | Authenticated |
| GET | `/api/v1/batches/` | Inventory batches (stock on hand) — read-only | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/adjustments/` | Stock adjustment CRUD (`user` = request user, read-only). **Negative** `qty_adjusted` deducts through FIFO; **positive** reopens the **newest** batch of the variant, whatever its `current_qty` is (so a correction against an out-of-stock variant restocks it). Refusals are **400**: `qty_adjusted = 0` → `{"qty_adjusted": ["qty_adjusted must not be 0 …"]}`; positive with **no batch history** for the variant → `{"code": "NO_BATCH_HISTORY", "detail": "…", "variant_id": N}`; negative beyond stock on hand → `{"code": "INSUFFICIENT_STOCK", "detail": "…", "shortfall": "11.00", "variant_id": N}`. Row creation and the stock move are ONE `atomic` block, so a refused adjustment leaves **no** `StockAdjustment` row. | Authenticated |
| GET | `/api/v1/alerts/` | System alerts (low stock, expiring, etc.) — **read-only**; every other verb on the collection/detail is **405** for every role, Admin included (alerts are system-generated, decision 06). Each row carries read-only `resolved_by`, `resolved_by_name` (full name, else username) and `resolved_at`, all `null` until resolved. | Authenticated |
| POST | `/api/v1/alerts/{id}/resolve/` | Resolve one alert: sets `is_resolved`, `resolved_by` = request user and `resolved_at` = server now, under a `select_for_update` lock on the alert row. Returns the serialized alert plus `detail: "Alert resolved."`. Already resolved → **400** `{"code": "ALERT_ALREADY_RESOLVED", "detail": "Alert N was already resolved."}` and the first resolver is kept. Unknown id → **404**. | Stock Manager / Store Manager / Admin (`IsInventoryRole`, P2 Ruling) |

### 3.4 `apps/pos` — checkout, customers, sales, receipts

| Method | Path | Purpose | Auth |
| --- | --- | --- | --- |
| GET | `/api/v1/customers/` | Customer list (walk-in, regular, contractor), including `total_credit_limit` | Cashier / Stock Manager / Store Manager / Admin |
| POST/PUT/PATCH | `/api/v1/customers/` | Create or update a customer. Sending **`total_credit_limit`** requires Store Manager / Admin — any other role gets **403** `{"code": "CREDIT_LIMIT_FORBIDDEN", "detail": …}` and **nothing is written** (a cashier who could raise a limit would void decision 08's credit block) | Cashier / Store Manager / Admin (credit limit: Store Manager / Admin) |
| DELETE | `/api/v1/customers/{id}/` | Delete a customer. Refused with **409** `{"code": "CUSTOMER_IN_USE"}` when sales, quotations, orders, ledgers or requisitions still reference the row (they are `PROTECT`) — deactivate instead | Store Manager / Admin |
| POST | `/api/v1/transactions/` | **Checkout** — body: `{customer, source, items[], payments[]}`; runs `process_sale` (server-priced lines, FIFO stock deduction on base units, payment allocation, OR generation, collectibles posting if underpaid). Honours `Idempotency-Key` (see *Idempotency* above). Failures are **400** `{code, detail}`: `INVALID_SALE` (line/qty/payment shape), `INSUFFICIENT_STOCK`, `CREDIT_LIMIT_EXCEEDED` (+ `limit`/`outstanding`/`shortfall`), `WALK_IN_CANNOT_OWE`, `NO_OPEN_SHIFT`; **409** `IDEMPOTENCY_KEY_REUSED`. **`source=RETURN` is a different contract** — body `{customer, source:'RETURN', original_transaction?, items[], payment_method, reason}`; see *Returns* below | Cashier / Store Manager / Admin |
| *(none)* | `/api/v1/transactions/{id}/` | **A completed sale is immutable.** `PUT`, `PATCH` and `DELETE` are **not routed**: every role — Admin included — gets **405**. `grand_total`, `customer`, `status` and the OR number answer for the same money forever; a correction is a `source=RETURN` transaction against the original, never an edit of it | — (405) |
| GET | `/api/v1/transactions/` | Sales history (with items, payments, receipt). **Own rows only** for a cashier-only user (another till's row is **404**); a Stock Manager / Store Manager / Admin sees every sale. Filters: `?source=RETURN` isolates returns; `?q=<text>` is a **case-insensitive EXACT** match on `transaction_no` **or** the receipt's `or_number`, applied **after** the cashier scope — another till's number returns an empty page, not a hint that it exists (a substring match would turn the endpoint into a search box over the whole shop's history) | Cashier / Stock Manager / Store Manager / Admin |
| GET | `/api/v1/transactions/{id}/returnable/` | **Till pre-flight for a return.** Resolved through the caller's scoped queryset, so another cashier's sale is a plain **404**. Returns `{transaction_no, customer, source, returnable, reason_if_not, lines[], open_debt}`: `lines` is one entry per **selling unit** (`variant_uom`, `name`, `uom`, `sold_qty`, `returned_qty`, `remaining_qty`, `unit_price`), `open_debt` is what the sale's ledger still owes, and `reason_if_not` is the stable code the POST would refuse with (`RELEASE_NOT_RETURNABLE`, `RETURN_OF_RETURN`, `ORIGINAL_NOT_COMPLETED`) or `null` when the sale is reversible. All quantities/money are 2-decimal **strings** | Cashier / Stock Manager / Store Manager / Admin (sales readers) |
| GET | `/api/v1/transactions/daily_report/` | Today's totals: `{date, count, total_sales}`, aggregated over the same scope as the list (cashier = own sales) | Cashier / Stock Manager / Store Manager / Admin |
| GET | `/api/v1/payments/` | POS payments (read-only), scoped through their transaction's cashier | Cashier / Stock Manager / Store Manager / Admin |
| GET | `/api/v1/receipts/` | Official receipts (read-only), scoped through their transaction's cashier | Cashier / Stock Manager / Store Manager / Admin |
| GET/POST/PATCH/PUT/DELETE | `/api/v1/quotations/` | Quotations with nested items (`quotation_no` generated server-side, `created_by` = caller) | read: Cashier / Stock Manager / Store Manager / Admin — write: Cashier / Store Manager / Admin |
| GET/POST/PATCH/PUT/DELETE | `/api/v1/sales-orders/` | Sales orders with nested items (`order_no` generated server-side, `created_by` = caller) | read: Cashier / Stock Manager / Store Manager / Admin — write: Cashier / Store Manager / Admin |
| GET | `/api/v1/held-carts/` | List held (parked) carts — store-wide among POS roles | Cashier / Store Manager / Admin |
| POST | `/api/v1/held-carts/` | **Hold** — body: `{customer, notes, items[{variant_uom, qty, unit_price}]}`; parks the cart without touching stock | Cashier / Store Manager / Admin |
| GET | `/api/v1/held-carts/{id}/` | Retrieve a single held cart with items | Cashier / Store Manager / Admin |
| DELETE | `/api/v1/held-carts/{id}/` | **Void** a held cart — permanent delete, no stock change | Cashier / Store Manager / Admin |
| POST | `/api/v1/held-carts/{id}/complete/` | **Complete** — body: `{customer?, payments[]}`; feeds items into `process_sale` (requires open shift) then deletes the cart. Honours `Idempotency-Key` (see *Idempotency* above): a retry after the cart was deleted returns the original sale with **200**, not 404 | Cashier / Store Manager / Admin |
| POST | `/api/v1/shifts/open/` | **Open shift** — body: `{opening_float}`; one open shift per cashier enforced at DB level (400 `SHIFT_ALREADY_OPEN` if already open) | POS role (Cashier / Store Manager / Admin) |
| POST | `/api/v1/shifts/{id}/close/` | **Close shift** — body: `{closing_count}`; sets status=CLOSED, returns Z-reading (transaction_count, gross_sales, cash_sales, card_sales, gcash_sales, expected_drawer, variance, `held_cart_count`). `held_cart_count` is the number of `HeldCart`s still parked by the shift's cashier — **advisory only**: it never blocks the close and never deletes the carts (decision 06 record-and-warn) | POS role (Cashier / Store Manager / Admin) |
| GET | `/api/v1/shifts/current/` | Current cashier's open shift, or 404 `No open shift`. The shift body carries read-only `held_cart_count` (same advisory, own carts only) | Authenticated (own shift only) |
| GET | `/api/v1/shifts/` | Shift list (own shifts for cashier, all for manager/admin); each row carries read-only `held_cart_count` | Authenticated |

> ⚠ **Returns (decision 05, Phase 3).** `POST /api/v1/transactions/` with `source=RETURN` reverses a sale. Body: `{customer, source:'RETURN', original_transaction?, items[{variant_id, qty}], payment_method, reason}`. Every rule below is enforced **before the first write** — a refused return leaves no RETURN row, no restock, no payment, no ledger movement and no audit row.
>
> | Rule | Answer |
> | --- | --- |
> | Open shift | **400** `NO_OPEN_SHIFT` — a refund is money out of a drawer, and a drawer is a shift. The return is recorded against the caller's OPEN shift |
> | Reason | **400** `RETURN_REASON_REQUIRED` — non-empty, ≤255 chars, stored in `notes` |
> | Linked original, non-manager | **403** `UNLINKED_RETURN_FORBIDDEN` — a cashier returns against the receipt in hand; an unlinked return is a Store Manager / Admin correction (their screen is Phase 5) |
> | Original is a direct-till sale **not** rung by this cashier | **404** (hidden ≠ forbidden — the original is resolved through the caller's scoped queryset) |
> | Original is a return | **400** `RETURN_OF_RETURN` |
> | Original is a requisition release (`source=REQUISITION`) | **400** `RELEASE_NOT_RETURNABLE` |
> | Original is not `COMPLETED` | **400** `ORIGINAL_NOT_COMPLETED` |
> | Qty above what is left | **400** `RETURN_QTY_EXCEEDED` + `{variant_uom, sold, already_returned, requested}` (2-decimal strings) |
>
> **Qty cap:** per **selling unit** (`VariantUOM`), the cumulative returned qty across all returns linked to the original may not exceed the qty **sold on the original**. Read from `SalesItem` lines, so a pre-linkage sale that never recorded `SalesItemDeduction` rows is capped too; two lines of the same selling unit in one request count as one quantity. The original transaction row is `select_for_update`-locked for the whole block, so concurrent returns serialize and cannot together exceed the cap.
>
> **Money is DEBT FIRST:** if the original sale has a collectible ledger with `balance_due > 0` (OPEN / PARTIAL / OVERDUE), the ledger is locked and reduced by `min(return_value, balance_due)`, flipped to `PAID` at zero (else `PARTIAL`), and the reduction is written as a `CollectiblePayment` with `payment_method='RETURN_CREDIT'`, `official_receipt_no` = the **return's** `transaction_no`, `processed_by` = the cashier. Only the **excess** leaves the drawer: the return's `Payment` row is `-excess` in the requested method, and **no Payment row at all is written when the excess is 0**. So `compute_z_reading`'s `cash_refunds` is the cash excess only.
>
> **201 body** is the serialized RETURN transaction plus `refund_summary: {return_value, debt_reduced, cash_refund, refund_method, ledger_id, ledger_balance}` (2-decimal strings; `ledger_id`/`ledger_balance` are `null` when the sale had nothing owing). The `RETURN` audit row names the return number, the original number, the debt reduced and the cash refunded.

### 3.5 `apps/collectibles` — utang / accounts receivable

| Method | Path | Purpose | Auth |
| --- | --- | --- | --- |
| GET | `/api/v1/ledgers/` | Outstanding receivable entries (+ nested payments) | Cashier / Store Manager / Admin |
| GET | `/api/v1/ledgers/aging/` | **Aging report** — overdue/open balances grouped by customer | Cashier / Store Manager / Admin |
| GET/POST/PUT/PATCH/DELETE | `/api/v1/ledger-payments/` | Collectible payments (posts against a ledger and moves `balance_due` in one atomic block). **Read + create only**: a payment row is a receipt of money, so PUT/PATCH/DELETE are **405** | read: Cashier / Store Manager / Admin — `POST`: Cashier / Store Manager / Admin |

> ℹ **A return settles utang before cash (decision 05):** a `source=RETURN` transaction against a credit sale writes a `CollectiblePayment` with `payment_method='RETURN_CREDIT'` (not a POS `Payment`), so the ledger history shows why the balance dropped. Only the excess becomes a `Payment` row on the return.
>
> ℹ **Ledgers are read-only (Phase 2):** `POST/PUT/PATCH/DELETE /api/v1/ledgers/` no longer exist (**405** for everyone, including managers). A ledger is opened by `process_sale` / `release_materials` and moved only by `POST /api/v1/ledger-payments/`, so `balance_due` cannot be rewritten by hand. The previous `PATCH` allowed any Django `is_staff` account to set a balance.
>
> ℹ **Receivables readers are narrower than sales readers:** a Stock Manager may read `/transactions/` (the stocker Sales tab) but gets **403** on `/ledgers/` — customers' debts are not inventory data.

> ℹ **Route note (fixed):** collectible payments were previously registered at `/api/v1/payments/`, which collided with the POS `payments` route and made them unreachable. They now live at **`/api/v1/ledger-payments/`**. Nested payments are still also visible inside `/api/v1/ledgers/` responses.

### 3.6 `apps/requisitions` — projects, material requests, tokens

| Method | Path | Purpose | Auth |
| --- | --- | --- | --- |
| GET/POST/PATCH/DELETE | `/api/v1/projects/` | Construction project CRUD | Read: any authenticated · Write: Site Foreman / Store Manager / Admin |
| GET/POST | `/api/v1/requisitions/` | Create a requisition (auto `req_number`, `requested_by` = current user, always starts `DRAFT`) / list them | Site Foreman / Store Manager / Admin — **read scope**: Store Manager / Admin see all, Site Foreman sees only `requested_by = self` (another foreman's row → **404**), everyone else → **403** |
| GET/PATCH/PUT/DELETE | `/api/v1/requisitions/{id}/` | Read / edit / delete one requisition. **`status` is action-only**: it is read-only here (a `status` in the payload is ignored, never applied), so only `submit` / `approve` / `reject` move it — a plain PATCH cannot walk a `DRAFT` to `APPROVED`/`RELEASED` around the approval, the token mint and the `REQ_APPROVE` audit row. Edits and deletes are refused once the requisition left `DRAFT` → **400** `{"code": "REQUISITION_LOCKED", "detail": "…"}` | Site Foreman (own only) / Store Manager / Admin |
| POST | `/api/v1/requisitions/{id}/submit/` | DRAFT → SUBMITTED | Site Foreman / Store Manager / Admin |
| POST | `/api/v1/requisitions/{id}/approve/` | SUBMITTED → APPROVED, generates `MaterialToken` (returns token UUID). Approving **your own** requisition → **400** `{"code": "SELF_APPROVAL", "detail": "…"}`, status unchanged, no token row — superusers included | Store Manager / Admin |
| POST | `/api/v1/requisitions/{id}/reject/` | SUBMITTED → REJECTED (own request may be rejected — only approval needs a second person) | Store Manager / Admin |
| GET/POST/PATCH/PUT/DELETE | `/api/v1/req-items/` | Requisition line items. Reads follow the parent requisition; writes only while the parent is `DRAFT`, otherwise **400** `{"code": "REQUISITION_LOCKED", "detail": "…"}` on create, edit and delete. **The target parent is resolved through the caller's row scope**: filing a line onto another foreman's requisition, or moving a line into one, is **404** with nothing written (the same hidden ≠ forbidden rule as the list) | Site Foreman (own requisitions) / Store Manager / Admin |
| GET | `/api/v1/tokens/` | Material tokens (read-only) — **a bearer credential** | Store Manager / Admin only (Cashier / Stock Manager / everyone else → **403**) |
| POST | `/api/v1/tokens/verify/` | Verify token — body: `{"token": "<uuid>"}` (UC-20) | Cashier / Store Manager / Admin (Stock Manager / foreman → **403**) |
> ⚠ **Requisition tokens are bearer credentials (Phase 2).** Whoever holds a `MaterialToken` UUID can release the goods on credit, so tokens are no longer readable by "any logged-in user": `GET /requisitions/` exposes `token` only to a Store Manager / Admin (any row) or the requesting Site Foreman, and the key is `null` for anyone else (it stays present, because the Flutter `Requisition` model decodes a nullable `token`). `GET /tokens/` is manager/admin-only. A cashier releases with the UUID the approver hands over — reading it is not part of their role.
>
> ⚠ **Separation of duties.** `approve` refuses the requester (`SELF_APPROVAL`, 400) before any write; `reject` does not — withdrawing your own request is harmless.
>
> ⚠ **Immutable after submit.** A requisition and its lines may only change while `DRAFT` (`REQUISITION_LOCKED`, 400). Otherwise items could be edited after approval and the token would release what nobody approved. Corrections go through a new requisition.
>
> ⚠ **`status` is action-only (Phase 2 review).** It is read-only on the serializer, so `PATCH {"status": "APPROVED"}` is ignored: approval needs the `approve` action, which is where separation of duties, the `MaterialToken` and the `REQ_APPROVE` audit row live.

| POST | `/api/v1/tokens/release/` | **Material release at POS** — body: `{"token": "<uuid>"}`; FIFO-deducts stock, creates `SalesTransaction`, posts to `CollectibleLedger` (UC-21/22). Quantities are **base units** (`RequisitionItem.quantity`) and are priced from the variant's **factor-1** `VariantUOM` (`default_selling_price`), resolved for **every remaining line before the first write**. A line whose variant has no factor-1 selling unit → **400** `{"code": "NO_BASE_UOM", "detail": "…"}` with the token still unused and nothing written (no sale, receipt, ledger or stock move). **Requires the caller's OPEN shift** (decision 03): with none → **400** `{"code": "NO_OPEN_SHIFT", "detail": "…"}` and the same empty outcome (token unused, stock unchanged, no `RELEASE` audit row). A successful release attaches that shift to its `SalesTransaction`, so it counts in the Z-reading's `transaction_count`/`gross_sales` while leaving `expected_drawer` untouched (a release books a collectible, never cash). Other token/state errors keep the plain `{"detail": "…"}` 400. | Cashier / Store Manager / Admin |

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
   | System alerts (`/alerts/`, incl. `resolve`) | `POST /alerts/{id}/resolve/` → Stock Manager / Store Manager / Admin (`IsInventoryRole`); all other verbs → **405** | Any authenticated |
   | Sales reads: `/transactions/` (+ `daily_report`), `/customers/`, `/payments/`, `/receipts/`, `/quotations/`, `/sales-orders/` | Cashier / Store Manager / Admin (`SalesReadPOSWrite`) | Cashier / Stock Manager / Store Manager / Admin — a **cashier-only** user sees only rows they rang (404 otherwise) |
   | Held/parked carts (`/held-carts/`, incl. `complete`) | Cashier / Store Manager / Admin | Cashier / Store Manager / Admin (store-wide; `inventory` / `foreman` → 403) |
   | Payments & official receipts | read-only | Cashier / Stock Manager / Store Manager / Admin (scoped like their transaction) |
   | Collectible ledgers (`/ledgers/`, `/ledgers/aging/`) | **none** — 405 (`ReadOnlyModelViewSet`) | Cashier / Store Manager / Admin (`IsReceivablesReader`) |
   | Collectible payments (`/ledger-payments/`) | `POST` only: Cashier / Store Manager / Admin | Cashier / Store Manager / Admin |
   | Projects | Site Foreman / Store Manager / Admin | Any authenticated |
   | Requisitions (`/requisitions/`, incl. items and lines) | Site Foreman (own, `DRAFT` only) / Store Manager / Admin | Site Foreman (own only, others → 404) / Store Manager / Admin; cashier, stocker, groupless → 403 |
   | Requisition `submit` | Site Foreman / Store Manager / Admin | — |
   | Requisition `approve` / `reject` | Store Manager / Admin — not the requester (400 `SELF_APPROVAL`) | — |
   | Material tokens (`/tokens/`) | — (read-only) | Store Manager / Admin |
   | Token `verify` | Cashier / Store Manager / Admin | — |
   | Token `release` | Cashier / Store Manager / Admin | — |

   Superusers bypass all role checks. Frontend role route guards (`/admin/*` etc.) are now backed by matching API enforcement. `is_staff` is **not** API authority (decision 04); `/users/` has no `DELETE` (405) and `is_staff` is read-only via the API — see §3.2.
3. ~~**`tests.py` are still empty stubs**~~ — **FIXED**: 546 lines of real tests across all 5 apps (`users` 140, `requisitions` 128, `inventory` 121, `pos` 95, `collectibles` 62). Run with `docker compose exec backend python manage.py test`.
4. ~~No dedicated `reports` aggregation endpoints yet~~ — **FIXED**: new read-only `apps/reports` (§4b) with `sales-summary`, `inventory-valuation`, `stock-movements`, `requisition-history`; `daily_report` now accepts `?date=`.

