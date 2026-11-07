# SYSTEM ATLAS — BuildPro POS / Inventory System

> **Generated:** 2026-10-15 · **Refreshed:** 2026-11-07 (POS evolution Phase 1 re-verified in source: foreman role and approvals UI gone, `CPMS Service` account fenced to `/api/v1/integration/cpms/`, partial release with per-line availability, project-tagged utang, 80 mm receipt printing, unknown addresses land on the user's dashboard) · **Branch:** `feat/pos-evolution-phase-1`
> **Method:** every claim below was verified against source — imports, route tables, model FKs, serializer fields, viewmodel bodies. `README.md`, `PHASE_*.md` and `ENDPOINTS.md` were **not** trusted.
> **Companion:** [`docs/system-atlas.html`](./system-atlas.html) — interactive cockpit (KPIs, filterable Truth Matrix, guided study path).

---

## 1. Architecture

Two processes, one database. A Flutter client talks to a Django REST API; the API owns **all** business logic and persists to PostgreSQL 15. Every client screen reads live API data except static store-info constants on the two settings screens — zero `*MockData`/`Simulator` files remain in `lib/` (both deleted; only comments reference the mock era). The server is the trust boundary: Phase 1 (server price/UOM authority, `INVALID_SALE` validation, credit-limit block, locked `DocumentCounter`, `Idempotency-Key` de-dupe) · Phase 2 (Admin-group authority + `LAST_ADMIN`, cashier-own scoping, token secrecy) · Phase 3 (open-shift gate, debt-first returns with `RETURN_CREDIT`) · Phase 4 (catalog persistence, two-step receive+process, append-only records) · Phase 5 (`IsUserManagerRole`: Store Manager user-write with `USER_ADMIN_FORBIDDEN` guardrails, manager-only unlinked returns) · Phase 6 (unique `barcode_qr` per selling unit — factory EAN/UPC GS1-checked or auto-derived `QB` code; `?barcode=` lookup; till scans resolve the unit with server fallback; 50×30 mm Code 128 stickers from Products + Receiving; per-unit code edit) · POS evolution Phase 1 (`CPMS Service` role behind `CpmsFencedJWTAuthentication`: 403 `CPMS_SCOPE` outside `/api/v1/integration/cpms/`; CPMS pushes approved requests, the POS keeps a read-only copy and releases what is in stock — `PARTIAL` keeps the token alive; utang carries the project). Contract for CPMS: [`docs/integration/CPMS-CONTRACT.md`](./integration/CPMS-CONTRACT.md) (v0.1, provisional).

```mermaid
flowchart LR
  subgraph Client["Flutter client — flutter/"]
    UI["features/*/views<br/>38 routes"]
    VM["features/*/viewmodels<br/>18 viewmodels"]
    NET["core/network/api_client.dart<br/>Dio + JWT refresh + Idempotency-Key + getAll page walk"]
    CAT["data/services/catalogue_service.dart<br/>brands + uoms + categories (Phase 4)"]
    SEC["TokenStore seam<br/>secure / prefs-per-platform"]
    UI --> VM --> NET
    NET -. tokens .-> SEC
  end
  subgraph Server["Django REST — backend_django/"]
    URLS["config/urls.py<br/>/api/v1/* (28 router paths)<br/>+ /api/v1/integration/cpms/ (6 paths)"]
    AUTH["users/authentication.py<br/>CpmsFencedJWTAuthentication<br/>403 CPMS_SCOPE outside the namespace"]
    APPS["apps/users · inventory · pos<br/>collectibles · requisitions · reports · integration"]
    SVC["services.py<br/>process_sale · process_return · release_materials<br/>import_request · close_requisition · project_payables<br/>next_number · replayed_transaction"]
    URLS --> AUTH --> APPS --> SVC
  end
  CPMS["CPMS (separate repo)<br/>CPMS Service account"]
  DB[("PostgreSQL 15<br/>35 models")]
  NET -- "HTTP :8000" --> URLS
  CPMS -- "/api/v1/integration/cpms/" --> URLS
  SVC --> DB
```

**Request lifecycle.** The two oldest paths, plus the Phase 1 checkout contract:

```text
login_page → AuthViewmodel → AuthService → POST /api/v1/auth/login/ → SimpleJWT
products_page → ProductsViewmodel → InventoryViewmodel.load() → GET /products/ + /batches/
checkout → PosTransactionViewmodel (owns attempt key) → POST /transactions/ [Idempotency-Key]
  → process_sale: validate → shift gate → server price → base_qty × CF → FIFO → receipt
```

`InventoryViewmodel` is the product list's **only** home (decisions 11/12).

---

## 2. Data model

Core erDiagram, derived from actual `ForeignKey`/`OneToOneField` declarations. Phase 1 additions marked ★.

```mermaid
erDiagram
  Category       ||--o{ Product : "category"
  Brand          ||--o{ Product : "brand"
  UnitOfMeasure  ||--o{ ProductVariant : "base_uom"
  Product        ||--o{ ProductVariant : "product"
  ProductVariant ||--o{ VariantUOM : "variant"
  UnitOfMeasure  ||--o{ VariantUOM : "uom"
  ProductVariant ||--o{ InventoryBatch : "variant"
  ProductVariant ||--o{ StockAdjustment : "variant"
  ProductVariant ||--o{ SystemAlert : "variant"
  Supplier       ||--o{ PurchaseOrder : "supplier"
  PurchaseOrder  ||--o{ POItem : "po"
  PurchaseOrder  ||--o{ GoodsReceipt : "po"
  GoodsReceipt   ||--o{ GoodsReceiptItem : "★ lines"
  POItem         ||--o{ GoodsReceiptItem : "po_item"
  ProductVariant ||--o{ POItem : "variant"
  GoodsReceipt   ||--o{ InventoryBatch : "receipt"
  Customer       ||--o{ Quotation : "customer"
  Quotation      ||--o{ QuotationItem : "items"
  Quotation      ||--o| SalesOrder : "quotation"
  Customer       ||--o{ SalesOrder : "customer"
  SalesOrder     ||--o{ SalesOrderItem : "items"
  SalesTransaction ||--o{ SalesItemDeduction : "deductions"
  Customer       ||--o{ SalesTransaction : "customer"
  SalesTransaction ||--o{ SalesItem : "items"
  SalesTransaction ||--o{ Payment : "payments"
  SalesTransaction ||--o{ OfficialReceipt : "receipts"
  VariantUOM     ||--o{ SalesItem : "variant_uom"
  Customer       ||--o{ CollectibleLedger : "customer"
  SalesTransaction ||--o{ CollectibleLedger : "transaction"
  CollectibleLedger ||--o{ CollectiblePayment : "collectible"
  Customer       ||--o{ Project : "customer"
  Project        ||--o{ Requisition : "project"
  Project        ||--o{ CollectibleLedger : "project (null for counter sales)"
  Requisition    ||--o{ RequisitionItem : "requisition"
  Requisition    ||--o| MaterialToken : "requisition (1:1)"
  VariantUOM     ||--o{ RequisitionItem : "variant_uom"
  User           ||--o{ AuditLog : "user"
  User           ||--o{ HeldCart : cashier
  Customer       ||--o{ HeldCart : customer
  HeldCart       ||--o{ HeldCartItem : items
  User           ||--o{ Shift : cashier
  Shift          ||--o{ SalesTransaction : shift
  DocumentCounter : "★ standalone lock row (prefix, day)"
```

**Backbone tables** (35 models, 7 apps — `reports` has views, `integration` has six API views, neither has models):

| App | Models | Notes |
| --- | --- | --- |
| `inventory` | 14 | `GoodsReceiptItem` per-receipt lines, `processed_at` lock flag; `Category` has no `is_active` (archive is UI-side) |
| `pos` | 14 | `DocumentCounter` locked numbering; `idempotency_key` + `request_hash` (partial unique on cashier+key); `Shift` FK on sale, return, release |
| `requisitions` | 4 | Project, Requisition, RequisitionItem, MaterialToken. `cpms_project_id` / `cpms_request_id` (unique, nullable) find a re-pushed copy; `requester_name` / `approver_name` are plain names (no foreman FK); statuses add `PARTIAL` and `CLOSED`; `RequisitionItem` keys on the selling `VariantUOM` with `released_qty` |
| `collectibles` | 2 | CollectibleLedger (+ nullable `project` FK, set by `release_materials` only; serializer adds `project_name`), CollectiblePayment |
| `users` | 1 | AuditLog (`User` extends `AbstractUser`, not `models.Model`). Roles: Admin, System Administrator, Store Manager, Stock Manager, Cashier, `CPMS Service` (in no `*_ROLES` list); `Site Foreman` retired by `requisitions.0002` |
| `integration` | 0 | `/api/v1/integration/cpms/`: `customers/`, `materials/`, `requests/` (import), `requests/{id}/` (read-back), `requests/{id}/close/`, `projects/{id}/payables/` — all `IsCpmsService` |

`Customer.total_credit_limit` is now nullable: null = unlimited, 0 = no credit (migration `pos.0008`).

---

## 3. Truth Matrix

Legend: 🟢 Live (screen's *primary* data comes from an API response) · 🟡 Partial (row Notes say which part) · 🔴 Mock (hardcoded) · ⚫ Dead (never called)

| Feature / Screen | UI file (`flutter/lib/features/`) | ViewModel / State | Backend endpoint | Status |
| --- | --- | --- | --- | --- |
| Login | `auth/views/login_page.dart` | `auth/viewmodels/auth_viewmodel.dart` | `POST /api/v1/auth/login/` | 🟢 Live |
| Token refresh / logout / me | — (via `ApiClient`) | `auth_viewmodel` | `/auth/refresh/` `/auth/logout/` `/auth/me/` | 🟢 Live |
| Health probe | — | `data/services/health_service.dart` | `GET /api/health/` | 🟢 Live |
| Admin dashboard | `dashboard/views/admin_dashboard.dart` | `dashboard/viewmodels/admin_overview_viewmodel.dart` | `GET /api/v1/reports/sales-summary/` + transactions + inventory | 🟢 Live |
| Inventory dashboard | `dashboard/views/inventory_dashboard.dart` | `inventory/viewmodels/inventory_viewmodel.dart` | products + batches + adjustments | 🟢 Live |
| Inventory stock list | `inventory/views/inventory_stock_page.dart` | `inventory/viewmodels/inventory_viewmodel.dart` | `GET /api/v1/batches/` | 🟢 Live |
| Low stock | `inventory/views/inventory_low_stock_page.dart` | `inventory_viewmodel` | `GET /api/v1/alerts/` | 🟢 Live |
| Stock movements | `inventory/views/inventory_stock_movements_page.dart` | `inventory_viewmodel` | `GET /api/v1/adjustments/` | 🟡 Partial |
| Products | `products/views/products_page.dart` | `products/viewmodels/products_viewmodel.dart` | `GET /api/v1/products/` + `/batches/` | 🟢 Live |
| Categories | `categories/views/categories_page.dart` | `CategoriesViewModel` (live CRUD + archive/restore) | `GET/POST/PATCH /api/v1/categories/` | 🟢 Live |
| Suppliers | `suppliers/views/suppliers_page.dart` | `suppliers_purchases_viewmodel` → `SupplierRepository` | `GET /api/v1/suppliers/` | 🟢 Live |
| Purchases / PO | `suppliers/views/purchases_page.dart` | `suppliers_purchases_viewmodel` → `SupplierRepository` | `GET /api/v1/purchase-orders/` | 🟢 Live |
| POS transaction | `pos/views/pos_transaction_page.dart` (receipt dialog prints an 80 mm PDF via `pos/widgets/receipt_document.dart`) | `pos/viewmodels/pos_transaction_viewmodel.dart` | `POST /api/v1/transactions/` [+ `Idempotency-Key` ★] | 🟢 Live |
| Sales dashboard | `sales/views/sales_dashboard_page.dart` | `inventory_sales_viewmodel` (`loadSummary` → server tiles, client fold fallback) | `GET /api/v1/reports/sales-summary/` | 🟢 Live |
| Sales transactions | `sales/views/sales_transactions_page.dart` | `inventory_sales_viewmodel` | `GET /api/v1/transactions/` | 🟢 Live |
| Sales returns | `sales/views/sales_returns_page.dart` | `inventory_sales_viewmodel` + `sales_unlinked_return_dialog` (Store Manager/Admin only) | `GET /transactions/?source=RETURN` + `POST` linked/unlinked | 🟢 Live |
| Sales reports | `sales/views/sales_reports_page.dart` | wraps shared `ReportsContent` in sales shell | `GET /api/v1/reports/*` | 🟢 Live |
| Quotations | `sales/views/sales_quotations_page.dart` | `sales/viewmodels/sales_module_viewmodel.dart` | `GET /api/v1/quotations/` | 🟢 Live |
| Sales orders | `sales/views/sales_orders_page.dart` | `sales_module_viewmodel` | `GET /api/v1/sales-orders/` | 🟢 Live |
| Receivables / utang | `sales/views/sales_receivables_page.dart` | `sales_receivables_viewmodel` (status chips + `recordPayment` + double-tap guard; project caption + search from `project_name`) | `GET /api/v1/ledgers/` + `POST /ledger-payments/` | 🟢 Live |
| Inventory sales | `sales/views/inventory_sales_page.dart` | `inventory_sales_viewmodel` | `GET /api/v1/transactions/` | 🟢 Live |
| Inventory returns | `sales/views/inventory_returns_page.dart` | `inventory_sales_viewmodel` | `GET /api/v1/transactions/?source=RETURN` | 🟢 Live |
| Inventory reports | `inventory/views/inventory_reports_page.dart` | static manager-access banner (read-only scope, D-02) | — | 🟢 Live (static) |
| Admin users | `admin/views/admin_user_management_page.dart` | `admin_users_viewmodel` (deactivate/reactivate + role change; Create admin-only) | `GET /users/` + `/stats/` + `PATCH` + `/assign_role/` (Store Manager admitted; admin rows hide actions for non-admin viewers) | 🟢 Live |
| Sales staff (Store Manager) | `admin/views/admin_user_management_page.dart` (sales shell) | same `admin_users_viewmodel` | same user endpoints via `/sales/staff` | 🟢 Live |
| Admin audit logs | `admin/views/audit_logs_page.dart` | `audit_log_repository` → `GET /api/v1/audit-logs/?page=` | `GET /api/v1/audit-logs/` | 🟢 Live |
| Admin reports | `admin/views/reports_page.dart` | `admin/viewmodels/admin_reports_viewmodel.dart` (requisition history labels Partly released / Closed / Cancelled) | `GET /api/v1/reports/*` | 🟢 Live |
| Admin monitoring | `admin/views/{sales,inventory}_monitoring_page.dart` | `ReportsRepository` live (`sales-summary` + `inventory-valuation`) | `GET /api/v1/reports/*` | 🟢 Live |
| Admin settings | `admin/views/settings_page.dart` | — (static inline consts, no backend) | — | 🟢 Live (static) |
| Requisition token flow (release counter) | `pos/views/material_release_page.dart` | `pos/viewmodels/material_release_viewmodel.dart` (per-line Full / Short / Unavailable / Already released) | `/tokens/verify/` `/tokens/release/` | 🟢 Live (`/pos/release`, posNavigation tab 2) |
| Collectibles writes (Record payment) | `sales/views/sales_receivables_page.dart` | `sales_receivables_viewmodel` | `POST /api/v1/ledger-payments/` | 🟢 Live |
| Goods receipts (receiving) | `inventory/views/inventory_receiving_page.dart` | `receiving_viewmodel` | `GET /purchase-orders/` + `POST /goods-receipts/` + `POST /:id/process/` | 🟢 Live |
| Brands / UOMs / variants / variant-UOMs | product add + category/brand dialogs | `catalogue_service` + `products_service` | `/brands/` `/uoms/` `/variants/` `/variant-uoms/` | 🟢 Live |
| Payments / receipts | **no UI** | — | `/payments/` `/receipts/` | ⚫ Dead |
| Project entity | **no UI** | — | `/projects/` (read-only; CPMS upserts projects on import) | ⚫ Dead |
| Requisition list | **no UI** (approvals pages deleted) | `RequisitionService.fetchRequisitions` / `RequisitionRepository` — no caller | `GET /api/v1/requisitions/` (read-only, `IsManagerRole`) | ⚫ Dead |
| POS held transactions | `pos/views/pos_held_transactions_page.dart` | `pos/viewmodels/held_cart_viewmodel.dart` | `GET /held-carts/` + hold/complete/void | 🟢 Live |
| POS shifts + Z-reading | `pos/views/pos_shift_page.dart` | `pos/viewmodels/shift_viewmodel.dart` | `GET /shifts/` + open/close/current | 🟢 Live |

**Score: 34 live · 1 partial · 0 mock · 3 dead (38 rows).** Client references **26 `/api/v1/` resource prefixes** (25 with a production caller — `/requisitions/` only from the orphaned `fetchRequisitions`) through 18 `ApiClient`-backed services (22 files); **38 `GoRoute`s**; **18 viewmodels** (19 files under `viewmodels/`, `pos_scan_result.dart` is a value type). Phase 1 removed `/admin/requisitions` and `/sales/requisitions`; the sales shell keeps `/sales/staff` and `/sales/reports`. The CPMS integration API has no Flutter caller by design (its client is CPMS) and is not a matrix row. No mock rows remain.

## 4. Vibe-Debt Hotspots

### Resolved

- Deleted legacy dashboards/reports screens (`7b47db3`, `a037cef`), `AdminMockData` (`02f82de`), `InventoryMockData` 907-line seed (Phase 4), Inventory Simulator dialog + callbacks (Phase 5); POS wiring misconception corrected (screen-scoped VMs are deliberate, decision 11); `pos_dashboard`/`sales_dashboard` orphans removed.

### Duplicate / overlapping files

| Files | Verdict |
| --- | --- |
| `sales/viewmodels/sales_module_viewmodel.dart` vs `sales/viewmodels/inventory_sales_viewmodel.dart` | Split by concern since 6C, one shared `sale_transaction.dart` transport — not two stacks. |
| `core/layout/{admin,inventory,sales}_skeleton_layout.dart` | Three near-clone shells; diff is mostly nav labels. Owned by cleanup plan 04. |
| ~~`inventory/viewmodels/inventory_mock_data.dart`~~ | Deleted Phase 4 — `InventoryViewmodel` loads all lists from server with honest loading state. |

- Naming: `dashboard/widget/` + `auth/widget/` stay **singular**; 8 others use `widgets/` (cosmetic).

### Wiring gaps (verified 2026-11-07)

- Uncalled by the client: receipts, payments, req-items, tokens (list), projects, requisitions (list — `fetchRequisitions` survives in service + repository with no caller since the approvals UI went). Called: everything else including brands, uoms, categories, suppliers, purchase-orders, audit-logs, `ledgers/aging`, `users/stats`, `variants`, `variant-uoms` (Phase 6: `GET /variant-uoms/?barcode=` exact match drives till scan-to-unit + server fallback).
- `HeldCartService.complete` now has production callers (`held_cart_viewmodel:156`, `pos_transaction_viewmodel:680`); `idempotencyKey` plumbing live.
- `User`/`AuditLog` APIs gate on the Admin group (`IsAdminRole`, Phase 2); `UserViewset` user-write additionally admits Store Manager via `IsUserManagerRole` with `USER_ADMIN_FORBIDDEN` guardrails (Phase 5).
- Requisitions are read-only for managers (`RequisitionViewSet`, `RequisitionItemViewSet`, `MaterialTokenViewSet` are `ReadOnlyModelViewSet` + `IsManagerRole`; `ProjectViewSet` read-only + `IsAuthenticated`). No create/submit/approve/reject anywhere — CPMS pushes, closes and reads back.
- Router `onException` (`routes.dart`) sends an address no route matches — e.g. a bookmarked `/admin/requisitions` — to `dashboardForRole(role)` (or login) instead of GoRouter's not-found page.

### Critical business logic (backend)

| Location | What it does | Client consumer? |
| --- | --- | --- |
| `apps/pos/services.py` `process_sale` | Validate → shift gate → server price → `qty × CF` → FIFO → payments → OR → ledger/credit-limit | ✅ POS checkout |
| `apps/pos/services.py` `next_number` + `DocumentCounter` | Locked per-day counter; seeds from max legacy suffix | ✅ sale, return, release |
| `apps/pos/services.py` `replayed_transaction` | Same key+hash → 200 replay; same key+different body → 409; scoped per (cashier, key, endpoint/cart) | ✅ checkout + held-cart complete |
| `apps/pos/services.py` `process_return` | Linked returns capped by negative deduction rows; restock at original batches × CF | ✅ returns pages |
| `apps/inventory/services.py` `process_goods_receipt` | Batches only the receipt's own `GoodsReceiptItem` lines; legacy delta path; `processed_at` lock | ✅ receiving page |
| `apps/inventory/services.py` `apply_stock_adjustment` | Zero-stock positive reopens newest batch; `NO_BATCH_HISTORY` otherwise | ✅ adjustments UI |
| `apps/requisitions/services.py` `verify_token` / `release_materials` | Per-line availability `FULL`/`SHORT`/`UNAVAILABLE`/`DONE`; release what is on the shelf → `PARTIAL` (token stays live) or `RELEASED` (token spent); `400 NOTHING_TO_RELEASE` writes nothing; non-releasable status → `REQUISITION_<STATUS>`; pre-write `NO_BASE_UOM` guard; ledger tagged with the project | ✅ release page |
| `apps/requisitions/services.py` `import_request` / `request_read_back` / `close_requisition` / `project_payables` | CPMS push (idempotent on `cpms_request_id`, upserts project, mints token) · read-back · close APPROVED/PARTIAL → `CLOSED` + token spent · per-project utang totals | — CPMS only (`apps/integration/views.py`) |
| `apps/users/authentication.py` `CpmsFencedJWTAuthentication` | Default auth class; `CPMS Service` member → 403 `CPMS_SCOPE` outside `/api/v1/integration/cpms/` (login/refresh exempt) | — fence, every request |
| `apps/collectibles/models.py` | Utang ledger + payment rollup | ✅ receivables + Record payment |

---

## 5. Read-First Study Path

| # | File | Read | Why it matters |
| --- | --- | --- | --- |
| 1 | `flutter/lib/main.dart` (~65 L) | whole file | Bootstrap + the `MultiProvider` list. Seven providers; `Products`/`PosTransaction` VMs are deliberately screen-scoped (decision 11). |
| 2 | `flutter/lib/routes/routes.dart` (~505 L) | `redirectFor` (pure), the role map, the 38 routes, `onException` | Single source of navigation truth. Roles gate by group; a Store Manager on `/admin/users` / `/admin/reports` is sent to the `/sales/*` twin (`salesTwinOf`), every other `/admin/*` to their dashboard; an unmatched address goes to the user's dashboard (`onException`). Splash owns restore with a 10 s abandon (`abandonRestore`); app time comes from `lib/core/time/app_clock.dart`, pinned in tests. |
| 3 | `flutter/lib/core/network/api_client.dart` (~275 L) | `init()`, interceptors, `post(path, {headers})` | The only network layer: Dio, JWT, refresh-on-401, `Idempotency-Key` passthrough. `init()` is **not idempotent** (`dio` is `late final`). |
| 4 | `flutter/lib/core/network/paged.dart` (~90 L) | whole file | Unwraps the DRF `{count,next,previous,results}` envelope in one place. `hasMore` comes from `next`, not row count. |
| 5 | `flutter/lib/features/inventory/viewmodels/inventory_viewmodel.dart` (~565 L) | `load()`, `isLoading`/`loadError`/`hasLoaded`, `batchesFor`, `stockOnHandFor` | The product list's ONLY home. `load()` mutates in place; on failure keeps the catalogue. |
| 6 | `flutter/lib/data/services/products_service.dart` (~260 L) | whole file | Live fetch through `getList<T>`; body with no `results` must **throw**. |
| 7 | `flutter/lib/core/widgets/async_view.dart` (~125 L) | whole file | Owns loading/error/empty/data for every data screen; builder never runs without data. |
| 8 | `pos_service.dart` + `apps/pos/services.py` `process_sale` | `checkout(idempotencyKey)`, `_failureFor` codes; then `process_sale` + `next_number` + `replayed_transaction` | **The money path (Phase 1).** Client sends `VariantUOM` id + selling qty + attempt key; server validates, prices, converts, locks the counter, de-dupes. Receipt screen renders **server** lines. |
| 9 | `ledger_entry.dart` + `ledger_service.dart` | `paidAmount`, `statusAt`, `projectName`, `fetchLedgers` | Receivables: `paidAmount` derived; server applies payments; `project_name` null for counter sales. |
| 10 | `flutter/lib/data/services/requisition_service.dart` + `models/requisition.dart` + `backend_django/apps/users/authentication.py` | `verifyToken`/`release` + `_plainCopy`/`_statusRefusalCopy`, `LineAvailability`; then the CPMS fence | No create/submit/approve/reject — CPMS owns the request. Token check returns per-line availability; `NOTHING_TO_RELEASE` and `REQUISITION_<STATUS>` map to readable copy. The fence is why the service account cannot read anything else. Contract: `docs/integration/CPMS-CONTRACT.md`. |
| 11 | `flutter/lib/data/services/user_service.dart` + `features/admin/viewmodels/admin_users_viewmodel.dart` | `fetchUsers`/`fetchUserStats`/`createUser` + `_message`; then `load`/`create`/filters | Strictest error split: 401 vs 403 vs load failure. `getList` parses eagerly. |

---

## 6. Verification Notes

**Verified against source 2026-11-07:** route tables (`routes.dart` 38 `GoRoute`s, `salesTwinOf`, `onException`), model declarations + FK targets (35 models; `RequisitionItem.variant_uom`, `CollectibleLedger.project`), `config/urls.py` + every `apps/*/urls.py` (28 router registrations + 6 integration paths), `permissions.py` role constants + `authentication.py` fence, `requisitions/services.py` + `exceptions.py` codes, `main.dart` provider list (7), `grep ApiClient` (18 backed services of 22 files), `grep /api/v1/` (26 resource prefixes), no `foreman` outside comments/migrations, no `requisitions_page`/`admin_requisitions_viewmodel` in `lib/`.

**Not verified:** `flutter run` pixels (standing caveat); true-concurrency behavior beyond qa-tester's 10-way live probe; CPMS repo (out of scope); actual paper output of receipt printing.

- Gates (2026-11-07): backend **Ran 599 OK**, flutter **+1284 ~221**, goldens **+221**, `flutter analyze` clean.
- Earlier atlas counts corrected on this pass: router paths were 28 all along (not 27); `main.dart` registers 7 providers (not 6).
- Known and deliberately unfixed: products toolbar `RenderFlex` overflow at ~1600px widths (`products_toolbar.dart:113`, `products_catalog_overview.dart:156`).
- Deferred minors (ledger `.superpowers/sdd/audit-remediation/progress.md`): release `remaining<=0` race, seed re-forcing Maria's limit, dead duplicate method check in `process_return`, credit-limit TOCTOU (fails closed), pre-`ae514ee` replay hashes now 409.
