# Returns Policy

**Status:** Locked 2026-10-24 (Grill). **Phases:** 3 (cashier), 5 (manager unlinked).

## Decision
- **Where:** new **Returns** tab in the Cashier till shell (`/pos/returns`). Flow: search original transaction (number/receipt) → pick lines + qty → reason → confirm → refund summary.
- **Who:** cashier with OPEN shift; return attaches shift.
- **Linked required** for cashiers; cumulative returned qty capped by original deduction rows; return-of-return rejected.
- **Unlinked:** Store Manager only, mandatory reason, audited (Phase 5 screen).
- **Money:** return value first reduces the original sale's OPEN/PARTIAL collectible balance; only excess is refunded as cash (CASH refund counts against drawer). Ledger flips to PAID when balance reaches 0.
- **Stock:** restock to the batches recorded in `SalesItemDeduction` (FIFO cost basis preserved), not newest batch.
- Returning a requisition release: out of scope this map (reject with 400 `RELEASE_NOT_RETURNABLE`).

## Security / RED tests
- Cashier unlinked return → 403. Qty above remaining → 400. Return without shift → 400.
- Credit sale 1000 with 600 unpaid, return 800 → debt 0, cash refund 200.
- Concurrent duplicate return requests cannot exceed cap.
