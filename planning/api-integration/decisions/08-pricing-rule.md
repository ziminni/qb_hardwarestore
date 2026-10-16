# Which Price the POS Charges

**Mode:** grill · **Status:** LOCKED 2026-10-15 · **Opened:** 2026-10-15
**Phase:** 0 — surfaced by research during [Product & Variant Client Model Shape](./02-product-variant-client-model.md).

## The question

When the catalogue and the POS display a price, which field is authoritative — and how is a variant's "current
cost" derived from per-batch values?

## Why it matters

The two candidate price fields **disagree by 75% in the seeded data**, so this is not a modelling nicety. It
decides what the cashier charges the customer.

| Source | Field | Seeded value (variant 6) |
| :--- | :--- | ---: |
| `VariantUom` (catalogue/list price) | `default_selling_price` | ₱315.00 |
| `InventoryBatch` (actual batch price) | `batch_selling_price` | ₱180.00 |

The same split applies to cost: `unit_cost_landed` is **per batch**, so a variant with several batches has
several costs and no single "cost". Something has to define what the UI shows.

This is the field the `CatalogueItem` assembler must fill, so it blocks Phase 0's assembler and Phase 1's
catalogue screen — not just Phase 3's checkout.

## Options

### A. `VariantUom.default_selling_price` is the price

The catalogue price is the single source of truth; batch prices are historical cost-basis data only. Simple,
predictable, and one price per selling unit regardless of which batch the stock came from.

- **Cost:** ignores `batch_selling_price` entirely, so that field becomes decorative.
- **Risk:** if the business actually intends per-batch pricing (clearance stock, cost changes), the POS
  overcharges or undercharges.

### B. `InventoryBatch.batch_selling_price`, resolved per batch at sale time

Price follows the batch FIFO actually deducts from — the most literally correct reading of the schema.

- **Cost:** the price can change mid-transaction as FIFO crosses a batch boundary, so one cart line may need
  splitting into two priced lines, and the receipt grows.
- **Risk:** materially more complex UI and receipt logic for a capstone demo.

### C. Latest batch wins (`order_by('-created_at').first()`)

One price per variant, derived from the most recent receipt.

- **Cost:** none of the API's own semantics; a rule invented by the client.
- **Risk:** unintuitive and hard to explain to a store owner.

## Recommendation

**Option A**, with `batch_selling_price` retained as display-only detail on the batch list. Rationale: a POS
needs exactly one unambiguous price per selling unit, `default_selling_price` is already the only field that
lives on the *selling* unit (`VariantUom`) rather than on a stock record, and it keeps the receipt one line per
cart line. Record the seeded ₱315 / ₱180 discrepancy as expected data, not a bug to reconcile.

For cost, recommend showing **latest batch `unit_cost_landed`** and labelling it explicitly rather than
presenting it as *the* cost — and not deriving a weighted average, which nothing in the schema supports
without summing every batch on every read.

## Resolution — LOCKED 2026-10-15

**Option A: `VariantUom.default_selling_price` is the charged price. `InventoryBatch.batch_selling_price`
becomes display-only.**

```dart
// the rule the CatalogueItem assembler applies
price = uom.defaultSellingPrice;   // 315.00 — what the customer is charged
// batch.batchSellingPrice         // 180.00 — shown on the batch list only, never charged
```

Consequences:

- A cart line's price never changes when FIFO crosses a batch boundary, so a receipt stays one line per cart
  line and totals need no re-derivation.
- `batch_selling_price` is charged nowhere; it remains stock detail on the batch list.
- The seeded ₱315 vs ₱180 gap is recorded as **expected data, not a bug to reconcile**.

Why A over the alternatives:

- **Per-batch pricing** would split one cart line into several priced lines mid-transaction, complicating the
  cart, the totals and the receipt — for a capability nothing has requested.
- **Latest-batch-wins** is a rule invented entirely by the client, with no basis in the API or schema, and it
  would silently re-price the catalogue every time stock is received.

### Cost, recorded as display-only

`unit_cost_landed` is per batch, so a variant with several batches has several costs and no single "cost".
Rule recorded: show the **latest batch's** `unit_cost_landed`, labelled explicitly as such, and never use it in
a charging calculation. No weighted average — nothing in the schema supports one without summing every batch on
every read. Revisit only if a margin report is ever needed.

### Evidence this decision rests on

| Fact | Value |
| :--- | ---: |
| `VariantUom.default_selling_price` (variant 6) | ₱315.00 |
| `InventoryBatch.batch_selling_price` (variant 6) | ₱180.00 |
| `InventoryBatch.unit_cost_landed` (variant 6) | ₱180.00 |

`batch_selling_price` equalling `unit_cost_landed` indicates zero markup in the seeded data, which is why the
batch price reads as a cost passthrough rather than a retail price.
