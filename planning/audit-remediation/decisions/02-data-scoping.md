# Data Scoping (Held Carts + Transactions)

**Status:** Locked 2026-10-24 (Grill). **Phase:** 2.

## Decision
| Resource | Cashier (`pos`) | Store Manager / Admin | Inventory / Foreman |
|---|---|---|---|
| `/transactions/` | own (`cashier=request.user`) | all | inventory keeps read for `source=RETURN` (stocker Returns tab) — scope to RETURN only |
| `/held-carts/` | list/resume/complete/void any (keeps decision 05) | all | **denied** (403) |

## Why
`HeldCartViewSet` and `SalesTransactionViewSet` have no queryset scoping; `IsPOSOrReadOnly` lets any authenticated user read.

## Security / RED tests
- Cashier B GET cashier A's transaction detail → 404.
- Inventory role GET `/held-carts/` → 403; GET `/transactions/?source=SALE` → empty/403.
- Foreman GET either → 403.
- Manager sees all.
