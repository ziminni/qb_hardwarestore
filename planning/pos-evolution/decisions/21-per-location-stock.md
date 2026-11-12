# Per-location stock and transfers

**Status:** Locked 2026-11-12 (by: me — owner answers; defaults marked *delegated*)
**Phase:** 9

## Context

Research (2026-11-12): on-hand is always `Sum(InventoryBatch.current_qty)` — server in `_check_low_stock`, `_on_hand_base`, `allocate_fifo`; Flutter sums `/batches/` client-side (`catalogue_assembler.dart`, `InventoryViewmodel.stockOnHandFor`). Batches have no location. `StorageLocation` + `Product.stored_at` are a label only (`apps/inventory/models.py:142-231`). Stock writers: receiving (`process_goods_receipt` → `_create_batch`), sale (`allocate_fifo` + `SalesItemDeduction`), release (`release_materials`), adjustments (`apply_stock_adjustment`), returns (`_restock_returned`), and (Phase 8) supplier returns.

## Decisions

1. **Migration:** all existing stock of a product is placed in its **Stored at** location. `Stored at` from then on means the product's **home location**. (by: me)
2. **Selling / releasing:** stock is taken from the **home location first, then any other active location**, FIFO within each. Receipts, delivery slips and release results show where each line was actually taken ("Pick up: 3 at Store, 2 at Bodega"). (by: me)
3. **Transfers:** **one step, immediate.** The stock team records "move N UNIT from A to B"; stock moves at once with a numbered transfer slip and an audit row; batch cost and age travel with the stock. (by: me)
4. **Low stock:** one threshold per product on the **total across locations**; the Low stock page shows the per-location split. (by: me)

## Delegated defaults (owner may override)

- **Data shape:** a batch carries its location (`InventoryBatch.location`). A transfer moves quantity out of source batches (FIFO) into **new batches at the destination** that copy the source batch's receipt, landed cost and expiry, so FIFO age and cost survive the move.
- **Receiving:** a receipt line goes into the product's home location by default; the receiver may choose another active location per line.
- **Adjustments:** an adjustment names a location (default home); removal and addition apply there only.
- **Customer returns:** restock into the batches the sale drew from (already the rule), therefore into the location the stock left.
- **Supplier returns (Phase 8):** leave from the chosen receipt's batches at whichever location they sit.
- **Inactive location:** cannot receive, be adjusted into, or be a transfer destination; stock already there stays sellable and can be transferred out.
- **Who transfers:** Stock Manager, Store Manager, Admin (same as adjustments). Quantities in a chosen selling unit, converted to base with the whole-unit and two-decimal rules.
- **Availability exposed by the server:** a per-location on-hand read is added so the till/catalogue stop deriving location totals client-side from raw batches.

## Consequences

- Every stock writer gains a location dimension; locks stay batch-level in the existing orders.
- Till availability = total across active locations (a sale may draw from both).
- `StorageLocation` docstring ("a label, not a second stock ledger") and the Phase 5 out-of-scope note are superseded.
