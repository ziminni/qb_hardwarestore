# Sell by measure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Sell any weight from a bag and any length from a roll, with an exact
price, stock and FIFO cost. This includes items that already have history.
Make loose selling findable from Add Product.

**Architecture:** Quantity columns move to 6 decimals. A measured selling unit
stores the exact `measure_per_base` (40 kg/bag, 150 m/roll). One helper,
`to_base_qty`, turns any selling quantity into base units, dividing for measured
units. The FIFO allocator absorbs rounding dust so stock can reach exactly zero.
Flutter shows stock as "9 BAG + 30 KG" and gains a third "By weight or length"
choice, plus a "Sell loose" section on Add Product.

**Tech Stack:** Django 5 + DRF + PostgreSQL, Flutter (Windows), existing test
runners.

**Spec:** `planning/sell-in-parts/2026-11-27-sell-by-measure-design.md`

## Global Constraints

- Quantity: `max_digits=18, decimal_places=6`; money fields unchanged (`decimal_places=2`).
- `QTY = Decimal("0.000001")`; `CENT` only for money.
- Typed selling quantities: at most 2 decimals. Measured units accept fractions;
  whole units still raise `WHOLE_UNIT_QUANTITY`.
- `measure_per_base`: `max_digits=12, decimal_places=2`, > 1, one measured unit per variant.
- Dust tolerance = `to_base_qty(unit, Decimal("0.005"))`.
- No historical value changes; no rebase; no AI attribution in commits.
- Backend tests: copy to `/tmp/qbt/qa`, `fast_settings`, PostgreSQL `qbt_db2`,
  `--parallel 1`. Baseline 1,778 OK. Flutter baseline: 81 failures already exist, and no new ones are allowed.

## Review Focus

1. A cashier types 0.125 kg (3 decimals). Expected: a clear 400 refusal, not silent rounding. → Task 4 test.
2. The last metre of a 150 m roll after 149 one-metre sales. Expected: it sells and stock is exactly 0. → Task 4 test.
3. An existing item's stock, sales and report totals after the migration. Expected: identical. → Task 1 test.
4. A held cart reserves 7.5 kg while another till sells the rest of the bag. Expected: the reservation in base units is respected, and the shortfall message names a readable amount. → Task 4 test.
5. Values the API returns with 6 decimals ("9.750000"). Expected: the UI never shows more than 3 decimals. → Task 6 test.

---

### Task 1: Precision, the measured-unit field, the shared helpers

**Files:**
- Create: `backend_django/common/quantities.py`, `backend_django/common/tests_quantities.py`
- Modify: the `models.py` of inventory, pos, requisitions and bodega (the fields below); new migrations in each app
- Modify: the explicit serializer qty fields: `inventory/serializers.py` (321, 605, 608, 885, 900, 1751, 1848), `pos/serializers.py:601`, `bodega/serializers.py` (68, 83, 150, 151), `integration/serializers.py:91`

Fields that change to (18, 6):
- `ProductVariant.min_stock_threshold/max_stock_level`
- `VariantUOM.conversion_factor`
- `POItem.ordered_qty/received_qty`, `GoodsReceiptItem.qty`
- `InventoryBatch.initial_qty/current_qty`
- `StockAdjustment.qty_adjusted`
- `SupplierReturnLine.qty/base_qty`, `SupplierReturnDeduction.qty`
- `StockTransferLine.qty/base_qty`, `StockTransferMove.qty`
- `SalesItem.qty`, `SalesItemDeduction.qty`, `QuotationItem.qty`
- `SalesOrderItem.qty/fulfilled_qty/cancelled_qty`, `HeldCartItem.qty`
- `RequisitionItem.quantity/released_qty`
- `BodegaReleaseLine.qty`, `BodegaDeliveryLine.delivered_qty/good_qty/damaged_qty`

Add `VariantUOM.measure_per_base = DecimalField(max_digits=12, decimal_places=2, null=True, blank=True)`.

**Interfaces — Produces:**
- `common.quantities.QTY: Decimal`
- `to_base_qty(variant_uom, qty: Decimal) -> Decimal`: `(qty / measure_per_base).quantize(QTY)` if `measure_per_base`, else `(qty * conversion_factor).quantize(QTY)`
- `dust_tolerance(variant_uom) -> Decimal`: `Decimal(0)` unless measured, else `to_base_qty(variant_uom, Decimal("0.005"))`
- `typed_qty_error(qty: Decimal) -> str | None`: a message if `qty` has more than 2 decimals

- [ ] Write the tests:
  - `test_to_base_qty_plain_unit_matches_old_math`: factor 12, qty 2 → 24.
  - `test_to_base_qty_measured_divides`: per_base 150, qty 1 → `Decimal("0.006667")`; per_base 40, qty 3 → `0.075`.
  - `test_dust_tolerance`: per_base 40 → `0.000125`; plain unit → 0.
  - `test_typed_qty_error`: 0.125 → message; 7.5 → None.
  - `test_existing_values_survive_migration`: a batch with `current_qty=Decimal("9.75")` reads back `== Decimal("9.75")`.
- [ ] Run them and see them fail (import error).
- [ ] Implement `common/quantities.py`. Change the fields and run `makemigrations`. Change the serializer fields to (18, 6).
- [ ] Run `manage.py makemigrations --check` (expect clean), the new tests (pass), and the full backend suite (1,778 OK, or the baseline plus the new tests).
- [ ] Commit `feat(quantities): 6-decimal stock quantities and measured-unit field`.

### Task 2: Every conversion goes through `to_base_qty`

**Files:** `pos/services.py` (1598, 2848, 3075, 3090, 3379), `pos/serializers.py:999`, `inventory/transfers.py:74`, `requisitions/services.py` (220, 427), `inventory/services.py`; quantity `quantize(CENT)` sites in `inventory/services.py`, `pos/views.py`, `inventory/transfers.py`, `bodega/services.py`, `requisitions/services.py` (money ones keep `CENT`). Also `allocate_fifo`'s shortfall note: `{reserved:.2f}` → a trimmed format.

**Interfaces — Consumes:** Task 1 helpers.

- [ ] Grep check: `grep -rn "\* *[a-z_.]*conversion_factor\|conversion_factor *\*" apps | grep -v tests` returns only the rebase in `add_smaller_unit`.
- [ ] Full backend suite: no change in pass count (pure refactor for existing units).
- [ ] Commit `refactor(stock): one base-quantity conversion for every path`.

### Task 3: `add-measure-unit`

**Files:** `inventory/services.py` (`add_measure_unit`, next to `add_part_unit`), `inventory/views.py` (action next to `add_part_unit_action`, same permission and audit pattern), `inventory/serializers.py` (expose `measure_per_base` on the selling-unit serializer); test `inventory/tests_measure_units.py`; `ENDPOINTS.md` row.

**Interfaces — Produces:** `add_measure_unit(*, variant, uom, measure_per_base: Decimal, default_selling_price: Decimal, barcode_qr="", credit_markup_kind="NONE", credit_markup_value=Decimal(0), user=None) -> VariantUOM`; `POST /api/v1/variants/{id}/add-measure-unit/` body `{uom_id, measure_per_base, default_selling_price, barcode_qr?, credit_markup_kind?, credit_markup_value?}` → 201 with the variant payload. The selling-unit JSON gains `measure_per_base` (string or null).

- [ ] Tests:
  - `test_adds_kg_to_bag_with_sales_history`: no rebase; `conversion_factor == Decimal("0.025000")`; `measure_per_base == 40`.
  - `test_refuses_fractional_base`, `test_refuses_whole_target_unit`, `test_refuses_per_base_not_above_one`, `test_refuses_second_measured_unit`, `test_refuses_negative_price`: each 400 `INVALID_SELLING_UNIT`.
  - `test_cashier_forbidden`: 403.
  - `test_price_change_recorded`.
  - `test_smaller_unit_refusal_mentions_measure`.
- [ ] Implement until green, then run the full suite.
- [ ] Commit `feat(inventory): add a measured selling unit (kg per bag, m per roll)`.

### Task 4: Selling, returning and reserving by measure, with dust handling

**Files:**
- `inventory/services.py` (`allocate_fifo` gains `tolerance: Decimal = Decimal(0)`)
- pos sale, return, exchange, void and held-cart paths, quotation, sales order, requisitions, transfers, and bodega: pass `tolerance=dust_tolerance(vuom)` and refuse a typed qty with `typed_qty_error`, as 400 code `QTY_TOO_PRECISE`
- tests in `pos/tests_measure_sales.py`

Allocator rule: if `available < qty_needed <= available + tolerance`, set `qty_needed = available`. After taking from a batch, if `0 < batch.current_qty <= tolerance`, also take that remainder in the same allocation.

- [ ] Tests (40 kg bag at cost ₱215; 150 m roll at cost ₱1,250):
  - `test_sell_3kg_cost_is_three_fortieths`: deduction 0.075, cost ₱16.13.
  - `test_roll_sold_metre_by_metre_reaches_zero`: 150 sales; on-hand 0; summed cost within ₱0.01 of ₱1,250.
  - `test_30kg_bag`.
  - `test_return_2_5kg_restores_exact`.
  - `test_void_restores`.
  - `test_held_cart_reserves_7_5kg`.
  - `test_three_decimal_qty_refused`.
  - `test_existing_bag_sale_unchanged`.
  - `test_requisition_and_transfer_in_kg`.
  - `test_bodega_release_in_kg`.
  - `test_sales_summary_profit_includes_kg_line`.
- [ ] Implement until green, then run the full suite.
- [ ] Commit `feat(pos): sell, return and reserve by weight or length`.

### Task 5: Adjusting stock in the measured unit

**Files:** the stock adjustment serializer and service (`inventory/serializers.py:1343` area, `inventory/services.py:1100` area); tests in `inventory/tests_measure_units.py`.

**Interfaces:** the adjustment body accepts an optional `variant_uom_id`. When set, `qty` is in that unit and is stored as `to_base_qty`.

- [ ] Test `test_spill_half_kilo` (stores −0.0125 BAG). Then implement, run the suite, and commit `feat(inventory): adjust stock in kilos or metres`.

### Task 6: Flutter model, formatting and stock display

**Files:**
- `flutter/lib/data/models/product.dart` (`SellingUom.measurePerBase: double?`)
- `flutter/lib/core/format/format.dart` (`formatQuantity` with at most 3 decimals, trimmed; new `formatStockWithMeasure(double onHand, String baseCode, SellingUom? measured)` → "9 BAG + 30 KG")
- Use sites: the Stock page, low stock table, product details, and the POS picker's on-hand
- Tests: `flutter/test/core/format/measure_format_test.dart`

- [ ] Tests:
  - 9.75 with per_base 40 → "9 BAG + 30 KG"
  - 3.283333 with 150 M → "3 ROLL + 42.5 M"
  - 0.31 → "0 BAG + 12.4 KG"
  - no measured unit → the phase 1 wording is unchanged
  - "9.750000" → "9.75"
- [ ] Implement, then run `flutter analyze` and the tests.
- [ ] Commit `feat(stock): show bags plus kilos and rolls plus metres`.

### Task 7: "Add selling unit" with a By weight or length tab

**Files:** `selling_unit_fields.dart` (third `_AddUnitKind.measure` segment and a `_MeasureUnitFields` widget: fractional-unit picker, "per BAG" amount, price per unit, proportional price hint); `products_details_dialog.dart:257` and `products_form_dialog.dart:1629` labels → "Add selling unit"; `products_service.dart` `addMeasureUnit(int variantId, Map body)`; the repository and writes model; tests in `flutter/test/features/products/measure_unit_dialog_test.dart`.

- [ ] Tests:
  - the tab is shown
  - the save body is `{uom_id, measure_per_base: "40", default_selling_price}`
  - the tab is disabled with a note for a fractional base
  - the existing tests are updated for the new label
- [ ] Implement, then run analyze and the tests.
- [ ] Commit `feat(products): sell by weight or length from the unit dialog`.

### Task 8: "Sell loose" on Add Product, and POS/adjust inputs

**Files:**
- `products_form_dialog.dart`: for a whole base unit on create, show a "Sell loose" section with three checkboxes (½, ¼, By weight or length) and their fields. The locked switch's subtitle becomes "Selling by the half bag, the kilo or the metre? Use Sell loose below."
- The create flow: create the product, then the part and measure calls. On a failure, show the error and open the product in Edit.
- The POS qty dialog: a measured unit allows 2 decimals.
- The adjust dialog: a unit choice for variants with a measured unit.
- Tests in `flutter/test/features/products/sell_loose_section_test.dart` and the POS and adjust tests

- [ ] Tests:
  - picking ¼ and By weight results in both calls after the create
  - a failed second call shows an error and keeps the product
  - the POS accepts 7.5 for KG and refuses 7.555
- [ ] Implement, then run analyze and the full Flutter suite (no new failures against the baseline).
- [ ] Commit `feat(products): sell loose section on Add Product`.

### Task 9: End-to-end check

- [ ] Rebuild the throwaway stack (`qbt_api` bind mount, migrate) and the QA app.
- [ ] Walk through it:
  - add KG to Portland Cement, which has history
  - sell 7.5 kg and 0.35 m of wire
  - check that the Stock page shows "+ KG"
  - check the receipt
  - return 2.5 kg
  - check that the sales summary screen, PDF and Excel totals match
- [ ] Update `docs/sessions/` with a short note, `ENDPOINTS.md`, and the design doc's status line.
- [ ] Commit `docs: sell by measure session notes`.
