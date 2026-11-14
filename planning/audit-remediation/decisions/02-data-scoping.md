# Data Scoping (Held Carts + Transactions)

**Status:** Locked 2026-10-24 (Grill). **Phase:** 2.

## Decision
| Resource | Cashier (`pos`) | Store Manager / Admin | Inventory / Foreman |
|---|---|---|---|
| `/transactions/` | own (`cashier=request.user`) | all | inventory reads **all** transactions/payments/receipts (superseded at build: the stocker Sales tab reads every sale — P2 ruling); foreman denied |
| `/held-carts/` | list/resume/complete/void any (keeps decision 05) | all | **denied** (403) |

## Why
`HeldCartViewSet` and `SalesTransactionViewSet` have no queryset scoping; `IsPOSOrReadOnly` lets any authenticated user read.

## Security / RED tests
- Cashier B GET cashier A's transaction detail → 404.
- Inventory role GET `/held-carts/` → 403; GET `/transactions/?source=SALE` → empty/403.
- Foreman GET either → 403.
- Manager sees all.

## As built (Phase 2, 2026-10-24)

Also enforced: completed sales are immutable (no PUT/PATCH/DELETE); a cashier may only return their own sale (404 otherwise); ledgers read-only and ledger-payments create/read only; receivables readers = POS + manager + admin (stocker 403); non-managers cannot set `total_credit_limit`. See `ENDPOINTS.md` role matrix.
