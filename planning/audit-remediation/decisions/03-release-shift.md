# Release Shift Ownership

**Status:** Locked 2026-10-24 (Grill). **Phase:** 3.

## Decision
`release_materials()` requires the releasing cashier's OPEN shift (400 `NO_OPEN_SHIFT`) and sets `SalesTransaction.shift`. Z-reading counts it in transaction count and gross; expected cash drawer unchanged (release creates a collectible, not cash tender).

## Security / RED tests
- Release without open shift → 400, token stays unused, no stock moved.
- Release with open shift → appears in Z count/gross, `expected_drawer` unchanged.
- Double release of same token (concurrent) → exactly one succeeds.
