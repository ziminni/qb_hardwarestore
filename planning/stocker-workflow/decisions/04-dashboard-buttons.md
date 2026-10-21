# Decision 04 — Dashboard Action Buttons

**Locked:** 2026-10-21  
**Status:** ✅ Locked

## Buttons Audited

In `inventory_dashboard_content.dart`:

| Button | Current state | Decision |
|---|---|---|
| "Add product" | `onPressed: () {}` (no-op) | Navigate to `/inventory/products` |
| "Export" | `onPressed: () {}` (no-op) | **Delete the button** |

## Rationale

"Add product" is the expected shortcut to the Products page, which is already live.
Wiring it is a one-liner: `context.go(AppRoutes.inventoryProducts)`.

"Export" has no backend endpoint and no download logic anywhere in the client.
Leaving a silent button is misleading; removing it is cleaner than a disabled state
with a tooltip that implies future work.
