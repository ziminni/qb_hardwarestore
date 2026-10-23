# SYSTEM ATLAS — BuildPro POS / Inventory System

> **Generated:** 2026-10-15 · **Refreshed:** 2026-10-22 (incremental — stocker Phases 1-4 + sales-manager Phases 1-3 + admin Phases 1-3 re-verified in source; AdminMockData deleted) · **Branch:** `feature/backend-integration` (pushed, in sync with origin)
> **Method:** every claim below was verified against source — imports, route tables, model FKs, serializer fields, viewmodel bodies. `README.md`, `PHASE_*.md` and `ENDPOINTS.md` were **not** trusted.
> **Companion:** [`docs/system-atlas.html`](./system-atlas.html) — interactive cockpit (KPIs, filterable Truth Matrix, guided study path).

---

## 1. Architecture

Two processes, one database. A Flutter client talks to a Django REST API; the API owns **all** business logic and persists to PostgreSQL 15. As of 2026-10-22 every client screen reads live API data except static store-info constants on the two settings screens — and no `*MockData` file remains in the tree (admin_mock_data.dart deleted 2026-10-22). Cashier-workflow (Phases 1–4) added HeldCart/Shift models + Linux token storage; stocker Returns/Reports/Settings tabs still have no routes (MAP ready, unbuilt).

```mermaid
flowchart LR
  subgraph Client["Flutter client — flutter/"]
    UI["features/*/views<br/>32 screens"]
    VM["features/*/viewmodels<br/>17 viewmodels"]
    NET["core/network/api_client.dart<br/>Dio + JWT refresh"]
    SEC["TokenStore seam<br/>secure / prefs-per-platform"]
    UI --> VM --> NET
    NET -. tokens .-> SEC
  end
  subgraph Server["Django REST — backend_django/"]
    URLS["config/urls.py<br/>/api/v1/*"]
    APPS["apps/users · inventory · pos<br/>collectibles · requisitions · reports"]
    SVC["services.py<br/>process_sale · approve_requisition<br/>verify_token · release_materials"]
    URLS --> APPS --> SVC
  end
  DB[("PostgreSQL 15<br/>34 models")]
  NET -- "HTTP :8000" --> URLS
  SVC --> DB
```

**Request lifecycle.** Every feature below now completes the round trip end to end. The two oldest paths:

```text
login_page → AuthViewmodel → AuthService → POST /api/v1/auth/login/ → SimpleJWT
products_page → ProductsViewmodel → InventoryViewmodel.load() → GET /products/ + /batches/
```

`InventoryViewmodel` is the product list's **only** home (decisions 11/12). No hardcoded screens left (§3 all live/static).

---

## 2. Data model

Core erDiagram, derived from actual `ForeignKey`/`OneToOneField` declarations.

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
  Requisition    ||--o{ RequisitionItem : "requisition"
  Requisition    ||--o| MaterialToken : "requisition (1:1)"
  ProductVariant ||--o{ RequisitionItem : "variant"
  User           ||--o{ AuditLog : "user"
  User           ||--o{ HeldCart : cashier
  Customer       ||--o{ HeldCart : customer
  HeldCart       ||--o{ HeldCartItem : items
  User           ||--o{ Shift : cashier
  Shift          ||--o{ SalesTransaction : shift
```

**Backbone tables** (34 models, 6 apps — reports has views, no models):

| App | Models | Notes |
| --- | --- | --- |
| `inventory` | 13 | Category, Brand, UnitOfMeasure, Product, ProductVariant, VariantUOM, Supplier, PurchaseOrder, POItem, GoodsReceipt, InventoryBatch, StockAdjustment, SystemAlert |
| `pos` | 13 | Customer, SalesTransaction, SalesItem, **SalesItemDeduction**, Payment, OfficialReceipt, **Quotation, QuotationItem, SalesOrder, SalesOrderItem, HeldCart, HeldCartItem, Shift** |
| `requisitions` | 4 | Project, Requisition, RequisitionItem, MaterialToken |
| `collectibles` | 2 | CollectibleLedger, CollectiblePayment |
| `users` | 2 | User (+ role), AuditLog |

`InventoryBatch` is the FIFO layer — `process_sale` deducts stock across batches in order.

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
| Categories | `categories/views/categories_page.dart` | `inventory_viewmodel` (mock-seeded; archive local) | — (endpoint exists, uncalled) | 🟡 Partial |
| Suppliers | `suppliers/views/suppliers_page.dart` | `suppliers_purchases_viewmodel` → `SupplierRepository` | `GET /api/v1/suppliers/` | 🟢 Live |
| Purchases / PO | `suppliers/views/purchases_page.dart` | `suppliers_purchases_viewmodel` → `SupplierRepository` | `GET /api/v1/purchase-orders/` | 🟢 Live |
| POS transaction | `pos/views/pos_transaction_page.dart` | `pos/viewmodels/pos_transaction_viewmodel.dart` | `POST /api/v1/transactions/` | 🟢 Live |
| Sales dashboard | `sales/views/sales_dashboard_page.dart` | `sales/viewmodels/inventory_sales_viewmodel.dart` | `GET /api/v1/transactions/` | 🟢 Live |
| Sales transactions | `sales/views/sales_transactions_page.dart` | `inventory_sales_viewmodel` | `GET /api/v1/transactions/` | 🟢 Live |
| Sales returns | `sales/views/sales_returns_page.dart` | `inventory_sales_viewmodel` | `GET /api/v1/transactions/?source=RETURN` | 🟢 Live |
| Sales reports | ~~`sales/views/sales_reports_page.dart`~~ | consolidated into Admin reports | `GET /api/v1/reports/*` | ⚫ Deleted (`a037cef`) |
| Quotations | `sales/views/sales_quotations_page.dart` | `sales/viewmodels/sales_module_viewmodel.dart` | `GET /api/v1/quotations/` | 🟢 Live |
| Sales orders | `sales/views/sales_orders_page.dart` | `sales_module_viewmodel` | `GET /api/v1/sales-orders/` | 🟢 Live |
| Receivables / utang | `sales/views/sales_receivables_page.dart` | `sales/viewmodels/sales_receivables_viewmodel.dart` | `GET /api/v1/ledgers/` | 🟢 Live |
| Inventory sales | `sales/views/inventory_sales_page.dart` | `inventory_sales_viewmodel` | `GET /api/v1/transactions/` | 🟢 Live |
| Inventory returns | `sales/views/inventory_returns_page.dart` | `inventory_sales_viewmodel` | `GET /api/v1/transactions/?source=RETURN` | 🟢 Live |
| Inventory reports | ~~`reports/views/inventory_reports_page.dart`~~ | consolidated into Admin reports | `GET /api/v1/reports/*` | ⚫ Deleted (`a037cef`) |
| Admin users | `admin/views/admin_user_management_page.dart` | `admin/viewmodels/admin_users_viewmodel.dart` | `GET /api/v1/users/` + `/stats/` + `POST /auth/register/` | 🟢 Live |
| Admin audit logs | `admin/views/audit_logs_page.dart` | `audit_log_repository` → `GET /api/v1/audit-logs/?page=` | `GET /api/v1/audit-logs/` | 🟢 Live |
| Admin requisitions (approve/reject queue) | `admin/views/requisitions_page.dart` | `admin/viewmodels/admin_requisitions_viewmodel.dart` | `GET /api/v1/requisitions/` · `POST /{id}/approve/` · `POST /{id}/reject/` | 🟢 Live |
| Admin reports | `admin/views/reports_page.dart` | `admin/viewmodels/admin_reports_viewmodel.dart` | `GET /api/v1/reports/*` | 🟢 Live |
| Admin monitoring | `admin/views/{sales,inventory}_monitoring_page.dart` | `ReportsRepository` live (`sales-summary` + `inventory-valuation`) | `GET /api/v1/reports/*` | 🟢 Live |
| Admin settings | `admin/views/settings_page.dart` | — (static inline consts, no backend) | — | 🟢 Live (static) |
| Sales dashboard (legacy) | ~~`dashboard/views/sales_dashboard.dart`~~ | — | — | ⚫ Deleted (`7b47db3`) |
| POS dashboard (legacy) | ~~`dashboard/views/pos_dashboard.dart`~~ | — | — | ⚫ Deleted (`7b47db3`) |
| Requisition token flow (release counter) | `pos/views/material_release_page.dart` | `pos/viewmodels/material_release_viewmodel.dart` | `/tokens/verify/` `/tokens/release/` | 🟢 Live — reachable since cashier-workflow Phase 2 (`posNavigation` tab 2 → `/pos/release`) |
| Collectibles writes (Record payment) | `sales/views/sales_receivables_page.dart` | `sales_receivables_viewmodel` | `POST /api/v1/ledger-payments/` | 🟢 Live |
| Goods receipts (receiving) | `inventory/views/inventory_receiving_page.dart` | `receiving_viewmodel` | `GET /purchase-orders/` + `POST /goods-receipts/` + `POST /:id/process/` | 🟢 Live |
| Brands / UOMs / variant-UOMs | **no UI** | — | `/brands/` `/uoms/` `/variant-uoms/` | ⚫ Dead |
| Payments / receipts | **no UI** | — | `/payments/` `/receipts/` | ⚫ Dead |
| Project entity | **no UI** | — | `/projects/` | ⚫ Dead |
| POS held transactions | `pos/views/pos_held_transactions_page.dart` | `pos/viewmodels/held_cart_viewmodel.dart` | `GET /held-carts/` + hold/complete/void | 🟢 Live |
| POS shifts + Z-reading | `pos/views/pos_shift_page.dart` | `pos/viewmodels/shift_viewmodel.dart` | `GET /shifts/` + open/close/current | 🟢 Live |

**Score: 25 live · 2 partial · 5 mock · 7 dead (39 rows).** +2 since 2026-10-20 (held carts, shifts). History: 23 · 2 · 5 · 7 (mock-purge) ← 10 · 3 · 17 · 7 ← 9 · 3 · 17 · 8 ← 8 · 3 · 18 · 8 ← 7 · 3 · 20 · 8.

Grade history (full story in git log + `docs/sessions/`): Phase 1 lit the catalogue/stock/low-stock together off one `InventoryViewmodel.load()` — the two Partial rows are those whose **own** data stays local (mock-seeded categories; movements render server adjustments but sale/opening rows are local, and the serializer carries a delta with no before/after pair). Phase 2 deleted 190 lines of invented movement history and reads `alerts/` exactly as alerted. Phase 3 took POS 🟡→🟢 (real `VariantUom.id` keys, server receipt, `InsufficientStock`→400, `cashier` read-only). Phase 6 + mock-purge (above) moved every remaining grade; former red scope (suppliers, audit logs, monitoring, settings) went live 2026-10-22; no mock rows remain. `InventoryViewmodel` still seeds its constructor from `InventoryMockData` (first paint never empty; 46 tests pin it) — replaced on load.

## 4. Vibe-Debt Hotspots
- ✅ **RESOLVED 2026-10-17:** underpayment flow reachable (dialog warns instead of refusing). Lesson kept: the dead code survived a phase because nothing tested the **seam** between dialog and `_pay`.

### Duplicate / overlapping files

| Files | Verdict |
| --- | --- |
| ~~`dashboard/views/pos_dashboard.dart`~~ | ⚫ **Deleted 2026-10-20** (`7b47db3`; orphan widgets followed in `f9e7ceb`). |
| ~~`dashboard/views/sales_dashboard.dart`~~ | ⚫ **Deleted 2026-10-20** (`7b47db3`). |
| `sales/viewmodels/sales_module_viewmodel.dart` vs `sales/viewmodels/inventory_sales_viewmodel.dart` | **Split by concern since 6C, shared wire models.** Module VM owns quotations/orders (`sales_module.dart` + `sale_transaction.dart`); inventory VM owns transactions/returns (`sale_transaction.dart` + `sales.dart`). Both import `sale_transaction.dart` — the overlap is one shared transport, not two stacks. The dead `SalesQuotation`/`SalesOrderRow` naming collision was resolved by rename. |
| ~~`reports/views/inventory_reports_page.dart` · `sales/views/sales_reports_page.dart`~~ · `admin/views/reports_page.dart` | **Consolidated 6B.1** (`a037cef`): one four-tab Admin screen; the two legacy screens deleted with routes, nav entries and tests updated. |
| `core/layout/{admin,inventory,sales}_skeleton_layout.dart` | Three near-clone shells; diff is mostly nav labels. Still duplicated — owned by cleanup plan 04, not a phase. |

- Naming: `dashboard/widget/` + `auth/widget/` stay **singular**; 8 others use `widgets/` (cosmetic).

### Wiring gaps

- ✅ **RESOLVED 2026-10-16 — this was never a defect.** `PosTransactionViewmodel` and `ProductsViewmodel` are
  still absent from `main.dart`'s `MultiProvider` (6 providers: auth, inventory, suppliers-purchases,
  inventory-sales, sales-module, product-tracking) and that is **correct**. Both are screen-scoped view state
  (decision 11); registering them would share one search box and one half-finished till cart across every
  navigation. `PosTransactionViewmodel` is provided at `pos_transaction_page.dart:35` and `ProductsViewmodel` at
  `products_page.dart`. The old "only 6 of 8 viewmodels are wired" framing assumed absence from `main.dart`
  meant not provided at all; it did not.
- ~~`admin/viewmodels/admin_mock_data.dart`~~ **DELETED 2026-10-22** (`02f82de`; zero runtime consumers after admin Phases 1–3 — audit logs + monitoring now live, settings inlined).

### Disconnected endpoints

- **Wired 2026-10-21** (`grep lib/ /api/v1/`): **30 distinct paths** — adjustments, alerts, auth login/logout/me/register, batches, customers, goods-receipts, ledger-payments, ledgers (+ aging), products, purchase-orders, quotations, the four reports, requisitions, sales-orders, tokens verify/release, transactions, users (+ stats). Uncalled by the client: brands, uoms, receipts, payments, req-items, tokens (list), projects, categories (names arrive nested in products). Now called: suppliers, purchase-orders, audit-logs.
- Counts refreshed 2026-10-21: **32 `GoRoute`s** in `routes.dart` (+4: `/pos/history`, `/pos/receivables`, `/pos/held`, `/pos/shifts`; `token_store.dart` seam added, `HeldCartViewmodel` app-scoped in `main.dart`). Screen-scoped rule (decision 11) still holds for `Products`/`PosTransaction` VMs.

### Critical business logic (backend)

`process_sale` gained its first client consumer in Phase 3 and `process_return` in 6C; requisitions
services are exercised by the approve queue and the material-release page. All six backend flows below have
now been observed through the app, not just read.

| Location | What it does | Client consumer? |
| --- | --- | --- |
| `apps/pos/services.py:28` `process_sale` | FIFO stock deduction, payment allocation, OR generation, collectibles posting on underpayment | ✅ **the POS checkout** (Phase 3) |
| `apps/pos/services.py` `process_return` | Linked returns share one cumulative accounting via negative deduction rows; refuses return-of-return and over-draw | ✅ **the returns pages** (6A.4 + 6C) |
| `apps/requisitions/services.py:18` `generate_req_number` | Requisition numbering | ✅ approve queue (Phase 5) |
| `apps/requisitions/services.py:33` `approve_requisition` | DRAFT→APPROVED, mints `MaterialToken` | ✅ approve queue (Phase 5) |
| `apps/requisitions/services.py:50` `verify_token` | Token validation for the POS | ✅ material release page |
| `apps/requisitions/services.py:82` `release_materials` | Token redemption → FIFO deduct → `SalesTransaction` → ledger | ✅ material release page |
| `apps/collectibles/models.py` | Utang ledger + payment rollup | ✅ receivables + Record payment (6C/decision 19) |

---

## 5. Read-First Study Path

Read in this order. Items 4–11 are the files **wired in Phases 0–6 + mock-purge** — read 1–3 first for the layers
they sit on, then the new paths top-down.

| # | File | Read | Why it matters |
| --- | --- | --- | --- |
| 1 | `flutter/lib/main.dart` (~90 L) | whole file | Bootstrap + the `MultiProvider` list. Six providers, and knowing **why** the other two are deliberately not here (decision 11) prevents re-adding them. |
| 2 | `flutter/lib/routes/routes.dart` (~360 L) | `redirectFor` (pure), the role map, the 28 routes | Single source of truth for navigation. `redirectFor` was extracted from the redirect closure so the routing rules are testable without rendering a dashboard. Roles gate by group: admin dashboard is Admin-only; `/admin/reports` and `/admin/requisitions` also admit `sales` (decisions 20); all `/inventory/*` require `inventory`. |
| 3 | `flutter/lib/core/network/api_client.dart` (~175 L) | `init()`, interceptors, `get`/`post`/`getList` | The only network layer: Dio setup, JWT storage, refresh-on-401. Note `init()` is **not idempotent** (`dio` is `late final`). |
| 4 | `flutter/lib/core/network/paged.dart` (~70 L) | whole file | **New (Phase 0).** Unwraps the DRF `{count,next,previous,results}` envelope in exactly one place (decision 03). `hasMore` comes from the `next` link, *not* the row count — the bug a review caught. |
| 5 | `flutter/lib/features/inventory/viewmodels/inventory_viewmodel.dart` (~250 L) | `load()`, `isLoading`/`loadError`/`hasLoaded`, `batchesFor`, `stockOnHandFor` | **New (Phase 1).** The product list's ONLY home, and therefore the hinge of the whole integration: loading it lights up products, inventory and POS at once. `load()` mutates in place (`_products`/`_batches` are `final List`) and on failure keeps the catalogue rather than emptying it. |
| 6 | `flutter/lib/data/services/products_service.dart` (~85 L) | whole file | **New (Phase 1).** The live fetch: both endpoints through `getList<T>`. Its test holds the decision-03 anti-regression — a body with no `results` list must **throw**, not return an empty catalogue. Worked example of the wired screen: `features/products/views/products_page.dart`. |
| 7 | `flutter/lib/core/widgets/async_view.dart` (~95 L) | whole file | **New (Phase 0).** Owns loading/error/empty/data for every data screen (decision 07); the precedence is baked in so the builder never runs without data. |
| 8 | `pos_service.dart` + `apps/pos/services.py:28` `process_sale` | payload/result types, `checkout`; then `process_sale` L28-111 | **Phase 3 — the money path.** `variant_id` is a `VariantUom` id, no `cashier` key (server assigns), cart clears only on 201. Server: one `transaction.atomic()` — FIFO, payments, OR, ledger. Observed live: 201 moved stock 95→93; short sale → 400 `INSUFFICIENT_STOCK`. |
| 9 | `ledger_entry.dart` + `ledger_service.dart` | `paidAmount`, `statusAt`, `fetchLedgers` | **Phase 4 T7 — receivables.** `paidAmount` is derived (`original − balance`); the server applies payments. `statusAt` compares at day granularity to match `due_date < today()`. Pagination followed: stopping at the 50th debt hides money. |
| 10 | `flutter/lib/data/services/requisition_service.dart` (~150 L) **+** `.../models/requisition.dart` (~200 L) | `approve`/`reject`/`verifyToken`/`release`, then the three wire shapes | **New (Phase 5 T1, decision 09).** Note what is ABSENT: no `createRequisition` and no `submit`. That is the decision made structural — a service without them cannot grow a button needing a Site Foreman, which is a CPMS identity that never logs into POS. Three DIFFERENT shapes (`Requisition`, `TokenVerification`, `ReleaseResult`) because the list row, the token check and the release result answer different questions. `token` is nullable because DRAFT/SUBMITTED rows have no token — verified live, and a regular DRF `Field` renders `None` where a `ReadOnlyField` **skips the key**. |
| 11 | `flutter/lib/data/services/user_service.dart` (~150 L) **+** `features/admin/viewmodels/admin_users_viewmodel.dart` (~180 L) | `fetchUsers`/`fetchUserStats`/`createUser` + `_message`; then `load`/`create`/filters | **New (mock-purge).** The newest stack and the strictest error split: 401 session-expired vs 403 permission-denied vs load failure. `getList` parses rows **eagerly**, so the malformed-row guard sits on the outer catch — an inner try around `items.toList()` misses (proven by a RED test failing as no-throw). Create errors live in `createError`, never in the page banner. |

---

## 6. Verification Notes

**Verified against source:** route tables (`config/urls.py`, `apps/*/urls.py`), model declarations + `ForeignKey` targets, `main.dart` provider list, `grep -rln ApiClient flutter/lib`, viewmodel bodies, `routes.dart` imports vs on-disk files.

**Not verified:**
- Gate 2026-10-20: `flutter analyze` clean, flutter **395/395**, backend **89/89**, `manage.py check` clean.
  `flutter/test/widget_test.dart` is tracked and green. (Was 291/46 after Phase 3; Phase 1 ended at 146.)
- The backend **was** re-scanned in this refresh: Phase 6 added `Quotation/QuotationItem`,
  `SalesOrder/SalesOrderItem` and `SalesItemDeduction` (erDiagram + backbone table updated above), and every
  service in the business-logic table now has a client consumer observed through the app.
- ✅ **2026-10-21 incremental refresh:** cashier-workflow Phases 1–4 verified in source (HeldCart + Shift models, `held-carts`/`shifts` router entries, `pos_held`/`pos_shifts` routes + pages + VMs, `token_store.dart` Linux-prefs seam, `navigatePos` 6-tab order); admin provider fix verified (`routes.dart` wraps `AdminDashboard` in route-scoped `AdminOverviewViewmodel` provider, RED→GREEN proven). Client now calls **30 distinct `/api/v1/` paths** (+held-carts, +shifts, +variants, +variant-uoms). Stocker tabs confirmed: Returns/Reports/Settings have no route constants and `navigateInventory` falls through at index 9 — MAP ready, unbuilt.
- ✅ **Corrected 2026-10-20 — 6D ran the app live.** `flutter run -d web-server` against the live backend:
  login as cashier/manager, till cart add, all sales screens, receiving flow, hash-navigated verification
  (auth is lost on full navigation, so pages were reached via location hash). Found and fixed two defects:
  `main.dart` awaiting desktop-only `window_manager` hung web boot (now `kIsWeb`-guarded), and the till never
  triggered an inventory load (now loads on open with banner + retry). #21 underpayment verified live:
  walk-in short-pay → 400 `WALK_IN_CANNOT_OWE`; Maria Santos short-pay → 201 + OPEN ledger.
- The three viewmodels not using an API layer were checked by import/usage grep, not by runtime tracing.
- Known and deliberately unfixed: the products toolbar overflows (`A RenderFlex overflowed by 9.7 pixels`) from
  `products/widgets/products_toolbar.dart:113` and `products_catalog_overview.dart:156`, visible at ~1600px
  widths. Found while testing Phase 1; UI work outside that phase.
