# Receiving Stock Through the UI

**Mode:** grill · **Status:** RESOLVED 2026-10-17 · **Opened:** 2026-10-17 (as a Fog of War item)
**Phase:** 6

## The question

The demo cannot create stock. Every unit in the database comes from `seed_demo`. Does it need to?

## What exists

```
POST /purchase-orders/                 wired in the client already
POST /goods-receipts/                  EXISTS, wired NOWHERE
POST /goods-receipts/{id}/process/     EXISTS, wired NOWHERE -> creates FIFO InventoryBatch rows
```

The receiving workflow is complete on the server and absent on the client: **no receiving page exists
on disk**, and `goods-receipts` appears in no Flutter file. The inventory sidebar has 11 entries and none
of them is receiving. So a purchase order can be created through the UI and then **never received**.

## Ruling (user, 2026-10-17)

**Build the receiving screen** in Phase 6: list purchase orders, record a goods receipt, process it into
FIFO batches.

## Why this one is different from the last three decisions

**It adds NO backend work.** All three endpoints already exist, so unlike [Sales Stack
Reconciliation](./05-sales-stack-reconciliation.md) and [Customer Returns](./15-customer-returns.md) this
decision does **not** widen the superseded invariant — it is one screen, one route and one sidebar entry.
It is the cheapest of the four scope decisions and the one with the largest effect on what the demo can
actually demonstrate, because it is the difference between a system that shows stock and one that
receives it.

## What this costs

- **One more screen in Phase 6**, with a create form (a receipt needs a PO, items and quantities) and a
  process action. The process action is the interesting half: it is what turns a receipt into batches.
- **The inventory sidebar goes from 11 entries to 12**, so the sidebar index for every inventory page
  after the insertion point must move — and `sidebar_index_consistency_test.dart` is the test that
  catches exactly that regression class, which it has already done once.

## The rejected alternatives

- *Leave receiving out of scope* keeps `seed_demo` as the only source of stock, but then the
  purchase-orders screen leads nowhere: a PO can be created and never received.
- *Read-only receiving history* makes the record visible but still cannot demonstrate the FIFO batch
  creation that `process/` performs — a screen that only ever shows what the seed made.
