# Decision 02 — Stocker Reports Scope

**Locked:** 2026-10-21  
**Status:** ✅ Locked

## Question

What should the stocker's "Reports" sidebar tab show, given that all four
`/api/v1/reports/*` endpoints are `IsManagerRole`-gated (Store Manager + Admin only)?

## Decision

Show a **"Manager access required"** banner page inside `InventorySkeletonLayout`.

No API call. No viewmodel. The page renders an icon + message:
> "Reports are available to Store Managers and above. Ask your manager for a summary."

## Rationale

- Stocker hitting any report endpoint gets 403. Silently showing a spinner that
  then fails is worse UX than a clear access message.
- A dedicated `inventory` role report endpoint is out of scope — it would require
  new backend work and a product decision about what data stockers should see.
- The tab must not crash or hang — a static informational page satisfies this.

## Deferred

Opening report endpoints to `inventory` role (or adding a read-only inventory
report) moved to **Fog of War** in MAP.md.
