# 01 — API Integration: Replace Mock Screens with Live Data

**Priority: P0.** This is the difference between the app *looking* finished and *being* finished.

**Goal:** every screen backed by an existing endpoint renders real data, with loading, error and empty
states. The endpoint contract is in `ENDPOINTS.md`; which screen maps to which endpoint is in the Truth
Matrix in `docs/SYSTEM_ATLAS.md`.

## Why this is the first priority

Of 10 feature modules, **only `auth` reaches the API** — verified by grepping for `ApiClient` across
`flutter/lib`. The other seven viewmodels render literal lists. The backend side is done: 24 router
routes plus 4 report paths exist and none are called by the client.

## Prerequisite: fix the frontend models before wiring anything

Wiring API calls against the current models will fail. This is the single most important blocking fact.

| File | Problem | Verdict |
| :--- | :--- | :--- |
| `flutter/lib/data/models/product.dart` | Reads `sku`, `cost_price`, `selling_price`, `current_stock`, `reorder_level`, `qr_identifier`, `storage_location`, and flattens `base_uom_code` / `variant_name`. **None exist** in any backend model or serializer. | Written against an imagined API. Must be rewritten. |
| `flutter/lib/data/models/inventory.dart` | Its 7 `fromJson` keys (`id`, `variant`, `user`, `adjustment_type`, `qty_adjusted`, `remarks`, `timestamp`) **exactly** match `StockAdjustmentSerializer`. | Correct, but misleadingly named — it holds the adjustment shape, not stock/batch. Rename or add a real batch model. |

The real `ProductSerializer` sends only:

```text
id, category, category_name, brand, brand_name, base_name,
description, image_url, is_active, variants, created_at, updated_at
```

Variant fields live on `ProductVariant`, reachable through the nested `variants` list — not flattened
onto `Product`. Any stock quantity comes from `InventoryBatch` (`/api/v1/batches/`), never from the
product payload.

## Prerequisite: register the missing viewmodels

`flutter/lib/main.dart` registers only **6 of 8** viewmodels. `PosTransactionViewmodel` and
`ProductsViewmodel` exist but are absent from the `MultiProvider` list, so they are unreachable. Register
them before wiring POS or Products, or the work will appear to do nothing.

## Gotcha: every list response is paginated

`backend_django/config/settings.py` sets `PAGE_SIZE = 50` with `PageNumberPagination`. Every list
endpoint returns:

```json
{ "count": 0, "next": null, "previous": null, "results": [] }
```

Read `response.data['results']`, not `response.data`. Note that `ENDPOINTS.md` currently claims
pagination is disabled — that is **wrong** and must be corrected, because trusting it produces a
runtime type error on every list screen.

## Order of attack

Work top to bottom; each row is independently demoable.

| # | Module | Endpoint(s) | Notes |
| :--- | :--- | :--- | :--- |
| 1 | `products` | `GET /api/v1/products/` | Blocked on the `product.dart` rewrite. Register `ProductsViewmodel` first. |
| 2 | `inventory` (stock list) | `GET /api/v1/batches/` | Needs a real batch model, not the adjustment-shaped one. |
| 3 | `categories` | `GET /api/v1/categories/` | Simplest read; uses local state today, so add a viewmodel. |
| 4 | `suppliers` / purchases | `GET /api/v1/suppliers/`, `GET /api/v1/purchase-orders/` | One viewmodel already covers both screens. |
| 5 | `pos` | `GET /api/v1/products/` then `POST /api/v1/transactions/` | The money path. Register `PosTransactionViewmodel`; the checkout call returns the finished sale. |
| 6 | `sales` | `GET /api/v1/transactions/`, `GET /api/v1/ledgers/` | Beware the two parallel sales stacks — see `04-cleanup.md`; wire one, not both. |
| 7 | `admin` | `GET /api/v1/users/`, `/users/stats/`, `/audit-logs/` | One shared mock object feeds 7 admin screens; replace it once, centrally. |
| 8 | `reports` | `GET /api/v1/reports/*` | Three report screens, one backend surface — see `04-cleanup.md`. |

## The pattern to copy

`features/auth/viewmodels/auth_viewmodel.dart` is the only correct example in the repo:
`View → ViewModel → Repository → Service → ApiClient`. `sales_module_viewmodel.dart` is the canonical
*mock* pattern being replaced. Do not invent a third shape.

Every wired screen needs three states it currently lacks entirely (all lists are synchronous today):
loading, error, and empty. A screen that renders a spinner forever on a 500 is not finished.

## Acceptance

- No viewmodel renders a hardcoded list; `*_mock_data.dart` is deleted.
- Every screen demonstrates loading, error and empty states.
- A list screen works against a real 50+ row response (proves the pagination envelope is handled).
- `flutter analyze` is clean.
