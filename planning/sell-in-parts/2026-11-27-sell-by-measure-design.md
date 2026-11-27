# Sell by measure: any weight from a bag, any length from a roll — design

Date: 2026-11-27. Phase 2 of [sell in parts](2026-11-27-sell-in-parts.md), which
covered halves and quarters. Branch: `feat/sell-by-measure`.

## Why

At the final defense, the panel asked how the store sells part of a bag of cement.
Phase 1 handles ½ and ¼. A real counter also sells **3 kg or 7.5 kg** of cement from
a bag, and **0.5 m or 35 cm** of wire, rope or hose from a roll. Each of these
loose sales needs its own price, and stock, cost and profit must stay correct.
Products that **already have sales history** must get this too, without rewriting
past records.

Clerks also could not find halves and quarters. On Add Product the "Allow
fractional quantity?" switch is greyed out for BAG and nothing points to the
right place. The "Add pack unit" button hides the option, and it only appears
after the product is saved.

## Goals

* Any whole-counted item (BAG, ROLL, BOX…) can also sell in a measured unit
  (KG, M, L, or any unit where `is_whole = False`). The clerk sets how many of
  that unit one base unit holds (40 kg per bag, 150 m per roll) and a price per
  measured unit.
* This works for items that already have sales, adjustments and transfers.
  History is never rewritten.
* The cashier types amounts with up to 2 decimals of the measured unit:
  7.5 kg, 0.35 m (= 35 cm), 0.01 kg (= 10 g).
* Stock can be sold down to exactly zero. Rounding never leaves a ghost
  "0.000001 BAG" and never blocks the last metre.
* Stock reads the way the store talks: **9 BAG + 30 KG**, **3 ROLL + 42.5 M**.
* FIFO cost of a kilo is the batch's bag cost × the fraction sold, as for halves
  today, so profit per kilo is correct.
* Halves, quarters and selling by measure can be found from Add Product.

## Non-goals

* Scales, barcode weights, or label printing.
* Receiving, purchase orders and supplier returns in the measured unit. These stay
  in bags and rolls.
* Changing money precision. All prices and totals stay at 2 decimals.
* Converting an item's base unit (making cement counted in kilos). Phase 1 rejected
  that, because it rewrites history.
* A CM unit. 35 cm is entered as 0.35 M.

## Anti-goals (failure even if it "works")

* Any historical figure changes: past sales, stock movements, report totals,
  Z-readings.
* Stock that cannot reach exactly zero, or a sale refused for the last piece of
  a roll because of rounding.
* Every quantity in the app suddenly showing 6 decimals ("9.750000 BAG").
* Turning fractions on for a whole unit everywhere. 0.3 bag of nails must stay
  impossible unless that item has a measured unit.

## Approaches considered

1. **Wider quantity storage, stock stays in bags (chosen).** Quantity columns go
   from 2 to 6 decimals. A kilo is one more selling unit of the same item.
   History is untouched because old values are exact at 6 decimals. The cost is
   a wide but mechanical change: about 25 columns across 4 apps, about 9 places
   that convert quantities, and the matching Flutter inputs.
2. **Re-count the item in kilos/metres.** Exact at 2 decimals, and it already
   exists for items with no history (`add-smaller-unit` rebases). For items with
   sales it means multiplying every past deduction, batch and adjustment by 40.
   That rewrites the audit trail and breaks before/after reports. Rejected
   because existing items must be supported.
3. **Separate "loose" item filled by an "Open a bag" step.** Rejected in
   phase 1: cashiers skip the step on busy days and stock drifts.

**Why 6 decimals and not 4 (changed after the user raised metres):**
4 decimals only works when the measure per base unit divides 1,000 exactly
(10, 20, 25, 40, 50 kg). Wire rolls are commonly 75 m or 150 m, and 1 m of a
150 m roll is 0.00666… roll. No number of decimals stores that exactly. So
the design stores the exact measure-per-base number. It converts by dividing,
rounds to 6 decimals (an error of at most 0.0000005 roll ≈ 0.08 mm of wire, or
0.02 g of a 40 kg bag), and clears the leftover dust when a batch empties (see
"Dust"). With this, any bag or roll size works, 30 kg bags included.

## Design

### Data

* New quantity quantum `QTY = Decimal("0.000001")`, kept in one shared place.
  `CENT` stays for money only.
* Every **quantity** `DecimalField` becomes `max_digits=18, decimal_places=6`,
  which keeps the 12 integer digits. Money fields are unchanged. The
  migrations are `AlterField` only, with no data change. Known columns:
  * inventory: `VariantUOM.conversion_factor`, `POItem.ordered_qty/received_qty`,
    goods-receipt `qty`, `InventoryBatch.initial_qty/current_qty`,
    `StockAdjustment.qty_adjusted`, transfer line/move `qty/base_qty`, supplier
    return qty, variant stock thresholds;
  * pos: sales item qty, `SalesItemDeduction.qty`, return/exchange item qty,
    held-cart item qty, pick-up `qty/fulfilled_qty/cancelled_qty`;
  * requisitions: `RequisitionItem.quantity/released_qty`;
  * bodega: line `qty`, `delivered_qty/good_qty/damaged_qty`.
  The builder confirms the full list by grep (`decimal_places=2` on any field
  that is not money). Serializer `DecimalField`s for these values change the same
  way.
* `VariantUOM.measure_per_base` (new, nullable, `max_digits=12, decimal_places=2`):
  set only on a measured selling unit, e.g. `40.00` (kg per bag) or `150.00`
  (m per roll). Its `conversion_factor` is stored as `1 / measure_per_base`
  rounded to `QTY`, for display and old readers only.

### One conversion helper

`to_base_qty(variant_uom, qty) -> Decimal` replaces every
`qty * conversion_factor` (about 9 sites in pos, inventory/transfers,
requisitions, and pos serializers):

* measured unit: `(qty / measure_per_base).quantize(QTY)`
* any other unit: `(qty * conversion_factor).quantize(QTY)`. This gives the same
  values as today for existing units, because their factors and quantities have
  ≤ 2 decimals.

Every `quantize(CENT)` applied to a **quantity** becomes `quantize(QTY)`
(about 17 non-test sites). Money keeps `CENT`.

### Adding a measured unit

`POST /api/v1/variants/{id}/add-measure-unit/`
`{uom_id, measure_per_base, default_selling_price, barcode_qr?, credit_markup_*?}`

* Same roles as `add-part-unit` (Stock Manager, Store Manager, Admin). Audited.
* Refused (`INVALID_SELLING_UNIT`, with a plain reason) when: the base unit is
  already fractional (an item counted in M already sells 0.35 m today); the
  chosen unit is whole (`is_whole = True`); `measure_per_base` ≤ 1 or has more
  than 2 decimals; the variant already has a measured unit (one per variant); or
  the price is negative.
* Never rebases. Works the same with or without history.
* The `add-smaller-unit` refusal for an inexact factor points here instead of
  only to halves and quarters.

### Selling

* A measured unit accepts quantities with up to 2 decimals. Base whole units
  keep refusing fractions (`WHOLE_UNIT_QUANTITY`); halves and quarters stay whole
  counts.
* Price per line = qty × unit price, rounded to the cent, as today.
* FIFO deducts `to_base_qty(...)` from batches and records cost for exactly that
  amount, as for halves today.
* Returns, voids, exchanges, held-cart reservations, pick-ups, requisitions,
  transfers and bodega lines all go through `to_base_qty`. Restocking a returned
  2.5 kg gives back exactly what 2.5 kg deducted.

### Dust

Rounding to 6 decimals can leave a batch at a tiny non-zero amount, or ask for
a hair more than is left. Rule, applied in the FIFO allocator and in the
availability checks:

* `tolerance = to_base_qty(unit, 0.005)`, i.e. half of the smallest amount a
  cashier can type, in base units.
* If a request exceeds what is available by ≤ tolerance, it takes everything
  available.
* If a deduction leaves a batch with ≤ tolerance, that remainder is added to
  the same deduction row, so the batch reaches 0 and the cost is recorded.
  Nothing is lost from the ledger.

### Stock adjustments

For an item with a measured unit, the adjust dialog lets the clerk enter the
amount in the base or the measured unit (for example a spill of 0.5 KG). The
server stores base units through `to_base_qty`. Other items are unchanged.

### Display

* `formatQuantity` never shows more than 3 decimals and trims trailing zeros.
  Stored values like `9.750000` show as `9.75`.
* For an item with a measured unit, stock shows **whole base + remainder in
  the measured unit**: `9 BAG + 30 KG`, `3 ROLL + 42.5 M`, `0 BAG + 12.4 KG`.
  The remainder is rounded to 2 decimals of the measured unit. This applies to
  the Stock page, low stock, product details, and the POS item picker's
  "on hand".
* Phase 1's "1 opened BAG, ¾ left" wording stays for items with halves or
  quarters and no measured unit.
* Sales lines, receipts and history show the line in its selling unit
  ("7.5 KG Portland Cement"), as today.

### Making it findable (Flutter)

* **Add Product, whole base unit:** under the locked "Allow fractional
  quantity?" switch, a **"Sell loose"** section with three optional
  checkboxes: ½, ¼, and "By weight or length". The last one asks for the unit
  (KG, M…), how many per base unit, and a price. Each picked option shows its
  price field and the proportional price for comparison. On Save, the product
  is created, then `add-part-unit` / `add-measure-unit` are called. If one of
  those fails, the product stays created, the error is shown, and the product
  opens in Edit with the same choices filled in.
* The locked switch's subtitle points to this section ("Selling by the half bag,
  the kilo or the metre? Use Sell loose below.").
* **Edit / product details:** "Add pack unit" becomes **"Add selling unit"**.
  The dialog gets a third tab, **By weight or length**, next to "Pack or other
  unit" and "Sell in parts".

## Testing (must pass before merge)

* Backend full suite on PostgreSQL (`--parallel 1`; baseline 1,778 OK) plus new
  tests:
  * an item with existing bag sales gets a KG unit; 3 kg sells; FIFO cost =
    3/40 of the bag cost; old sales and report totals are unchanged;
  * a 150 m roll sold 150 × 1 m reaches exactly 0 with no refusal, and the cost
    sums to the roll's cost within ₱0.01;
  * a 30 kg bag works;
  * a return of 2.5 kg restores exactly; void restores; an exchange works;
  * a held cart reserves 7.5 kg; a requisition, transfer and bodega line carry
    kilos correctly;
  * refusals: fractional base, whole target unit, factor ≤ 1, a duplicate
    measured unit, a 3-decimal qty;
  * migration on a copy of seeded data: every existing quantity is unchanged.
* Flutter: analyzer clean; no new failures against the master baseline (81
  failures already exist); new tests for the stock display, the Sell loose
  section, the third dialog tab, and 2-decimal input on measured units.
* Run the app on the throwaway stack: sell 7.5 kg of cement and 0.35 m of wire,
  and check the Stock page, a receipt, a return, the sales summary, and its
  PDF/Excel exports.

## Left to the builder

* Exact file layout, and where `QTY` / `to_base_qty` live (one shared module).
* The exact column list, from grep.
* Whether the PostgreSQL migrations need `SeparateDatabaseAndState`. They should
  not: plain `ALTER COLUMN TYPE numeric(18,6)` is fine at this data size.
* Wording of messages, following the existing plain style.
