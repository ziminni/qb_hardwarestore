# ENDPOINTS.md — Flutter Feature → Backend Endpoint Mapping

This document maps every **frontend feature** (`flutter/lib/features/`) to the **backend endpoints** it consumes. The backend is organized by **domain** (Django apps), not by screen — this is intentional and follows Django best practice. Frontend "features" like `categories`, `products`, and `suppliers` are all one data domain (`apps/inventory`), while `admin`/`auth` are handled by `apps/users`, and `dashboard`/`reports` are aggregations served by existing apps. Use this table instead of restructuring the backend.

---

## 1. Base URL & Authentication

| Item | Value |
|---|---|
| Base URL (dev) | `http://10.0.2.2:8000` (Android emulator) / `http://127.0.0.1:8000` (web/desktop) — see `API_CONNECTION_SETUP.md` |
| API prefix | `/api/v1/` |
| Auth scheme | JWT Bearer (`rest_framework_simplejwt`) |
| Header | `Authorization: Bearer <access_token>` |
| Health check | `GET /api/health/` (public, no auth) |

### API conventions (agreed — do not break)

| Topic | Convention |
|---|---|
| Pagination | **None for now** — list endpoints return full arrays (capstone-scale data). If data grows, migrate to DRF `?page=` before frontend relies on raw lists. |
| Error format | DRF default: `{"detail": "..."}` for auth/permission errors; `{"field": ["msg"]}` for validation errors. Frontend should read `detail` or the first field error. |
| 401 handling | Frontend retries once via `POST /auth/refresh/`; if that fails → logout to `/login`. |
| Null safety | Every account is created **with a role** (`group_name` required at registration), so `role` in user payloads is never `null`. |
| IDs | Integer PKs. Always serialize `id` in responses. |

---

## 2. Frontend Feature → Backend App (the big picture)

| Flutter feature folder | Backend app that serves it | Key endpoints |
|---|---|---|
| `features/auth` | `apps/users` | `/api/v1/auth/*` |
| `features/admin` | `apps/users` | `/api/v1/users/*`, `/api/v1/audit-logs/*` |
| `features/categories` | `apps/inventory` | `/api/v1/categories/*`, `/api/v1/brands/*`, `/api/v1/uoms/*` |
| `features/products` | `apps/inventory` | `/api/v1/products/*`, `/api/v1/variants/*`, `/api/v1/variant-uoms/*` |
| `features/inventory` | `apps/inventory` | `/api/v1/purchase-orders/*`, `/api/v1/goods-receipts/*`, `/api/v1/batches/*`, `/api/v1/adjustments/*`, `/api/v1/alerts/*` |
| `features/suppliers` | `apps/inventory` | `/api/v1/suppliers/*` |
| `features/pos` | `apps/pos` | `/api/v1/transactions/*`, `/api/v1/customers/*`, `/api/v1/receipts/*` |
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
|---|---|---|---|
| GET | `/api/health/` | Connectivity check for Flutter | Public |

### 3.2 `apps/users` — auth, admin, audit

| Method | Path | Purpose | Auth |
|---|---|---|---|
| POST | `/api/v1/auth/login/` | Login (username or email + password) → JWT pair | Public |
| POST | `/api/v1/auth/refresh/` | Refresh access token | Public (refresh token in body) |
| POST | `/api/v1/auth/register/` | Create account — **`group_name` is required** (roles: Admin, Stock Manager, Cashier, Store Manager); guarantees every account has a non-null `role` | Admin |
| POST | `/api/v1/auth/logout/` | Logout (blacklists refresh token, writes audit log) | Authenticated |
| GET | `/api/v1/auth/me/` | Current user profile + roles | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/users/` | User CRUD (admin). Query param: `?search=<term>` matches **username**, full name, or email | Admin |
| GET | `/api/v1/users/stats/` | Account summary for dashboard cards: `{total, active, inactive, roles_assigned}` | Admin |
| POST | `/api/v1/users/{id}/assign_role/` | Assign Group — body: `{"group_name": "Cashier"}` | Admin |
| POST | `/api/v1/users/{id}/remove_role/` | Remove Group — body: `{"group_name": "Cashier"}` | Admin |
| GET | `/api/v1/audit-logs/` | Immutable audit trail (read-only) | Admin |

Roles map to Django's built-in `Group`/`Permission` (see `apps/users/models.py` ERD mapping: USER → `apps_users.User`, ROLE → `auth.Group`).

### 3.3 `apps/inventory` — products, catalog, purchasing, stock

| Method | Path | Purpose | Auth |
|---|---|---|---|
| GET/POST/PATCH/DELETE | `/api/v1/categories/` | Category CRUD | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/brands/` | Brand CRUD | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/uoms/` | Unit-of-measure CRUD | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/products/` | Product CRUD | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/variants/` | Product variant CRUD | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/variant-uoms/` | Variant selling-UOM CRUD | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/suppliers/` | Supplier CRUD | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/purchase-orders/` | Purchase order CRUD (nested items) | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/goods-receipts/` | Goods receipt CRUD | Authenticated |
| POST | `/api/v1/goods-receipts/{id}/process/` | Process a receipt → FIFO `InventoryBatch` creation | Authenticated |
| GET | `/api/v1/batches/` | Inventory batches (stock on hand) — read-only | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/adjustments/` | Stock adjustment CRUD | Authenticated |
| GET | `/api/v1/alerts/` | System alerts (low stock, expiring, etc.) | Authenticated (admin to write) |
| POST | `/api/v1/alerts/{id}/resolve/` | Resolve an alert | Admin |

### 3.4 `apps/pos` — checkout, customers, sales, receipts

| Method | Path | Purpose | Auth |
|---|---|---|---|
| GET/POST/PATCH/DELETE | `/api/v1/customers/` | Customer CRUD (walk-in, regular, contractor) | Authenticated |
| POST | `/api/v1/transactions/` | **Checkout** — body: `{customer, source, items[], payments[]}`; runs `process_sale` (FIFO stock deduction, payment allocation, OR generation, collectibles posting if underpaid) | Authenticated |
| GET | `/api/v1/transactions/` | Sales history (with items, payments, receipt) | Authenticated |
| GET | `/api/v1/transactions/daily_report/` | Today's totals: `{date, count, total_sales}` | Authenticated |
| GET | `/api/v1/payments/` | POS payments (read-only) | Authenticated |
| GET | `/api/v1/receipts/` | Official receipts (read-only) | Authenticated |

### 3.5 `apps/collectibles` — utang / accounts receivable

| Method | Path | Purpose | Auth |
|---|---|---|---|
| GET | `/api/v1/ledgers/` | Outstanding receivable entries (+ nested payments) | Authenticated |
| GET | `/api/v1/ledgers/aging/` | **Aging report** — overdue/open balances grouped by customer | Authenticated |
| POST/PATCH/DELETE | `/api/v1/ledgers/` | Ledger write operations | Admin (`IsAdminOrReadOnly`) |
| GET/POST/PATCH/DELETE | `/api/v1/ledger-payments/` | Collectible payments CRUD (posts against a ledger) | Authenticated |

> ℹ **Route note (fixed):** collectible payments were previously registered at `/api/v1/payments/`, which collided with the POS `payments` route and made them unreachable. They now live at **`/api/v1/ledger-payments/`**. Nested payments are still also visible inside `/api/v1/ledgers/` responses.

### 3.6 `apps/requisitions` — projects, material requests, tokens

| Method | Path | Purpose | Auth |
|---|---|---|---|
| GET/POST/PATCH/DELETE | `/api/v1/projects/` | Construction project CRUD | Authenticated |
| GET/POST/PATCH/DELETE | `/api/v1/requisitions/` | Requisition CRUD (auto `req_number`, `requested_by` = current user) | Authenticated |
| POST | `/api/v1/requisitions/{id}/submit/` | DRAFT → SUBMITTED | Authenticated |
| POST | `/api/v1/requisitions/{id}/approve/` | SUBMITTED → APPROVED, generates `MaterialToken` (returns token UUID) | Authenticated |
| POST | `/api/v1/requisitions/{id}/reject/` | SUBMITTED → REJECTED | Authenticated |
| GET | `/api/v1/req-items/` | Requisition line items | Authenticated |
| GET | `/api/v1/tokens/` | Material tokens (read-only) | Authenticated |
| POST | `/api/v1/tokens/verify/` | Verify token — body: `{"token": "<uuid>"}` (UC-20) | Authenticated |
| POST | `/api/v1/tokens/release/` | **Material release at POS** — body: `{"token": "<uuid>"}`; FIFO-deducts stock, creates `SalesTransaction`, posts to `CollectibleLedger` (UC-21/22) | Cashier / Store Manager / Admin |

---

## 4. Typical Frontend Flows (which endpoints to call, in order)

| Flow | Endpoint sequence |
|---|---|
| Login | `POST /auth/login/` → store tokens → `GET /auth/me/` → route to role dashboard |
| Product catalog page | `GET /products/` (+ `GET /categories/`, `GET /brands/` for filters) |
| Receiving stock | `POST /purchase-orders/` → `POST /goods-receipts/` → `POST /goods-receipts/{id}/process/` |
| POS checkout | `GET /products/` → `POST /transactions/` (one call does stock deduction + payments + OR) |
| Utang monitoring | `GET /ledgers/` → `GET /ledgers/aging/` → `POST /ledger-payments/` |
| Foreman requisition | `POST /requisitions/` → `POST /requisitions/{id}/submit/` → approver: `POST /requisitions/{id}/approve/` → POS: `POST /tokens/verify/` → `POST /tokens/release/` |
| Daily dashboard/report | `GET /transactions/daily_report/` (optional `?date=YYYY-MM-DD`) + `GET /ledgers/aging/` + `GET /alerts/` |

## 4b. Reports Endpoints (`/api/v1/reports/` — Store Manager / Admin only)

| Method | Endpoint | Purpose |
|---|---|---|
| GET | `/api/v1/reports/sales-summary/?from=YYYY-MM-DD&to=YYYY-MM-DD` | Daily sales totals (count, gross, VAT, discounts) + range totals. Defaults to last 30 days. |
| GET | `/api/v1/reports/inventory-valuation/` | Stock value at cost & retail, grouped by category + grand totals. |
| GET | `/api/v1/reports/stock-movements/?from=&to=` | Stock IN (goods receipts/day) vs OUT (adjustments by type). |
| GET | `/api/v1/reports/requisition-history/?status=&from=&to=` | Counts per status + filtered requisition list (max 200). `status` must be a valid Requisition status (DRAFT, SUBMITTED, APPROVED, REJECTED, PARTIAL, RELEASED, CANCELLED). |


## 5. Gaps / TODOs observed while writing this doc (backend)

1. ~~**Route collision** on `/api/v1/payments/`~~ — **FIXED**: collectible payments moved to `/api/v1/ledger-payments/`.
2. ~~**Role-level permissions not yet enforced per endpoint**~~ — **FIXED**: role permissions enforced via `apps/users/permissions.py`. Matrix:

   | Endpoint group | Write access | Read access |
   |---|---|---|
   | Auth (`login/`, `verify/`, `refresh/`) | Public / Authenticated | — |
   | Users CRUD, roles, audit logs, register | Django staff (`IsAdminUser`) | Django staff |
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

   Superusers bypass all role checks. Frontend role route guards (`/admin/*` etc.) are now backed by matching API enforcement.
3. **`tests.py` are still empty stubs** across all apps.
4. ~~No dedicated `reports` aggregation endpoints yet~~ — **FIXED**: new read-only `apps/reports` (§4b) with `sales-summary`, `inventory-valuation`, `stock-movements`, `requisition-history`; `daily_report` now accepts `?date=`.

