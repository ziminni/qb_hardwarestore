# Decision 01 — Stocker Returns Scope

**Locked:** 2026-10-21  
**Status:** ✅ Locked

## Question

What should the stocker's "Returns" sidebar tab show?

## Options Considered

| Option | Description |
|---|---|
| A — Read-only list | Show RETURN-source transactions. No form. Reuse existing VM. |
| B — Initiate-return form | Stocker fills form to record a return against a transaction. |
| C — Both | Table + initiate button. Full feature. |

## Decision

**Option A — Read-only list.**

`SalesTransactionViewSet` uses `IsPOSOrReadOnly` which grants `inventory` role full
read access (GET). The `InventorySalesViewmodel` already fetches
`GET /api/v1/transactions/?source=RETURN`. A thin `InventorySkeletonLayout` wrapper
with `selectedNavigationIndex: 9` is all that's needed — zero new backend code.

## Rationale

Unblocks the stocker story in one phase. Option C (initiate return form) requires a
`process_return` workflow decision (who initiates — cashier or stocker?) that isn't
sharp enough to specify now.

## Deferred

Option C moved to **Fog of War** in MAP.md.
