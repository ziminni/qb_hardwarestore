# Alert Resolve

**Status:** Locked 2026-10-24 (Grill). **Phase:** 2.

## Decision
`SystemAlertViewSet` resolve/write → Stock Manager (`inventory`) + Admin. Add `resolved_by` (FK user, SET_NULL) + `resolved_at` to `SystemAlert` (Research: model has only `is_resolved`, `apps/inventory/models.py` ~312) — migration required; audit event written.

## Security / RED tests
- Inventory resolve → 200 with resolver. Cashier/sales/foreman resolve → 403. Resolve already-resolved → 400.
