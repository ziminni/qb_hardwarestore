# Sell in parts (opened bags) — design and plan

Date: 2026-11-27. Raised by the panel at the final defense: a store opens a bag of
cement and sells part of it. The system must track what is left, its cost, and a
separate (usually higher) loose price.

## How the store works

A customer asks for a quarter or half bag. The cashier opens a sealed bag and sells
that part. Later customers buy the rest. Loose cement is priced above the bag price
divided by the parts, because the store carries the spill and the effort.

## Decision

Sell parts **from the same item**. No separate "loose" product and no "open a bag"
step: the sale itself deducts the fraction.

* A part unit is a normal selling unit of the variant: `½` (HALF) is 0.50 of the
  base unit, `¼` (QTR) is 0.25. ¾ is sold as 3 × ¼.
* Each part unit has its own price, so the loose premium is just its price.
* FIFO already deducts `qty × conversion_factor` base units and records the batch
  cost of exactly that amount, so profit per quarter is correct with no new logic
  (checked: 3 × ¼ deducted 0.75 bag at ₱215/bag).
* Stock shows the base unit with the fraction: `9.75 BAG` means 9 sealed and an
  opened bag with ¾ left. The Stock page says so in words.
* Spillage is written off with a normal adjustment (for example Damaged, 0.05 bag).

### Why not the alternatives

* **Separate loose variant with an "Open a bag" step**: one more task at the
  counter that gets skipped on busy days, so stock drifts.
* **Existing "smaller unit" path** (`add-smaller-unit`): built for a unit *inside*
  a pack (1 BOX = 24 CAN). With no sales history it re-bases the product onto the
  smaller unit (cement would become "40 QTR"); with history it needs an exact
  2-decimal factor. Parts are not that, so they get their own path and never rebase.
* **Per-unit fractional switch** (`UnitOfMeasure.is_whole`): shared by every
  product using that unit, so turning it on for cement bags would allow 0.3 bag of
  nails.

## Phase 1 (this change): halves and quarters

Backend
1. `POST /api/v1/variants/{id}/add-part-unit/` with
   `{parts: 2|4, default_selling_price, barcode_qr?, credit_markup_*?}`.
   Stock Manager / Store Manager / Admin. Creates the HALF or QTR unit of measure
   once (whole-counted), then a selling unit with factor 0.50 or 0.25. Never
   rebases. Refused (`INVALID_SELLING_UNIT`) when the base unit is already
   measured in fractions (KG, M, L…) or the part already exists. Audited.
2. The `add-smaller-unit` refusal for a factor that is not exact at 2 decimals
   now points to selling in parts.
3. Stock adjustment rows carry `user_name`.

Flutter
4. The unit dialog has three clear choices: bigger pack, smaller unit inside,
   and **sell in parts** (pick ½ or ¼, enter the loose price; the dialog shows the
   proportional price and the extra profit).
5. The Stock page shows "1 opened BAG, ¾ left" when a whole-counted item has a
   fraction on hand.
6. `INVALID_SELLING_UNIT` shows the server's reason instead of a generic sentence.
7. Stock adjustment history shows the user's name instead of "User 3".

## Phase 2 (next): any number of kilos

Goal: sell 3 kg or 7.5 kg from a 40 kg bag. 1 kg is 0.025 bag, which does not fit
the 2-decimal quantity columns.

Plan
1. Widen quantity precision to 4 decimals for stock movement columns:
   `VariantUOM.conversion_factor`, `InventoryBatch.initial_qty/current_qty`,
   `SalesItemDeduction.qty`, `StockAdjustment.qty_adjusted`,
   `StockTransferLine/Move` quantities, `GoodsReceiptItem.qty`,
   `RequisitionItem` quantities, bodega lines, held-cart reservations.
   Money stays at 2 decimals.
2. Replace every `quantize(CENT)` applied to a *quantity* with a `QTY` quantum
   (0.0001), keeping `CENT` for money. Audit the allocator, returns, transfers,
   receiving and reports for 2-decimal assumptions.
3. Add a per-variant "can be sold by weight" option: a KG selling unit with
   factor `1 / kg-per-bag` (0.025 for 40 kg), its own price per kg.
4. Show stock as "9 BAG + 30 KG" for such items.
5. Migration: widening decimals is safe for existing data (no rounding); run the
   full POS suite (about 1,500 tests) and a sale/return/report check before merge.
6. Flutter number inputs and formatters that assume 2 decimals for quantity.

Already possible today, worth knowing: a bag whose kilos divide into exact hundredths
(50 kg: 1 kg = 0.02 bag) already accepts a KG selling unit through
`add-smaller-unit`. A sale of 0.3 kg would deduct 0.006 bag, which 2-decimal
storage rounds. Phase 2 removes that rounding for every bag size.

Risk: wide but mechanical. Do it on its own branch after Phase 1 is in use.

## Found while testing (not part of this change)

These fail on `master` too (checked 2026-11-27 against the same 12 tests):

* Voiding a sale crashes: `FOR UPDATE cannot be applied to the nullable side of
  an outer join` (`apps.pos.tests_void_sale`, 3 tests).
* Supplier bills with zero payment terms: due date is None, and the payables
  list/aggregate error (`apps.inventory.tests_supplier_payables`, 3 tests).
* Query-count, numbering and return-model tests (6) drifted after the
  2026-11-25 commits.
* Flutter: stocker Returns/Settings pages, "Stock adjustments" naming, product
  toolbar overflow and two write-chain tests fail on `master` as well (13).
