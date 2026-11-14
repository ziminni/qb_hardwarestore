# Alert Resolve

**Status:** Locked 2026-10-24 (Grill). **Phase:** 2.

## Decision
`SystemAlertViewSet` resolve/write → Stock Manager (`inventory`) + Admin. Add `resolved_by` (FK user, SET_NULL) + `resolved_at` to `SystemAlert` (Research: model has only `is_resolved`, `apps/inventory/models.py` ~312) — migration required; audit event written.

## As built (2026-10-25)
The role sentence above is kept as written. The permission actually wired is the existing
`IsInventoryRole`, which admits **Stock Manager + Store Manager + Admin** — the same class the
rest of the inventory writes use (Phase 2 plan, step 2: "the existing class; ruling"). This is
recorded, not rewritten: the decision text said Stock Manager + Admin, the shipped class is the
broader trio, and a Store Manager can resolve an alert today.

## Security / RED tests
- Inventory resolve → 200 with resolver. Cashier/sales/foreman resolve → 403. Resolve already-resolved → 400.
