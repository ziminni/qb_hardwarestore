# Selling units after creation, the standard unit list and whole-number rules

**Mode:** grill · **Status:** ✅ Locked 2026-11-10 (by: me) · follows [How a product is sold](./15-product-packaging-units.md)

## Context

- `VariantUOM` has no `DELETE` (405) because sale lines `PROTECT` it; `variant`, `uom` and `conversion_factor` are frozen once sold or in a held cart (`SELLING_UNIT_IN_USE`); price and `barcode_qr` stay editable (Phase 6).
- `ProductVariant.base_uom` is fixed at creation (`INVALID_VARIANT`).
- Seed creates only BAG, PC, RL units; `POST /uoms/` exists for stock roles but has no screen.
- Whole-vs-fractional quantity is a client-only code list (`flutter/lib/core/units/whole_units.dart`). The server already rounds whole units in requisition release planning (`releasable_qty`), but sale, held-cart and return paths do not refuse a fractional whole-unit quantity.

## Decision

1. **Add selling unit** from the product details dialog for existing products, using the same fields as Add product step 2.
2. **Remove unused unit:** a selling unit that was never sold, held, returned or requested (no sale line, held-cart line or requisition line references it) can be removed; the factor-1 base unit can never be removed. Used units stay; their price and code remain editable as today.
3. **Standard unit list built in:** a data migration adds pc, bag, box, pack, roll, sheet, kg, g, m, cm, L, mL to every database (get-or-create by code, existing rows untouched). No in-app "new unit" screen; rare extras via Django admin.
4. **Server enforces whole numbers:** each unit carries a whole-number flag set by that migration (pc, bag, box, pack, roll, sheet = whole). Sale, held cart, return and release refuse fractional quantities for whole units with a coded 400. The app reads the flag from the server instead of its hard-coded list.

## Follow-up rulings (2026-11-10, by: me)

- Whole-number refusal also covers quotations, sales orders, purchase orders, goods receipt and stock adjustments (the last three by the variant's base unit flag).
- CPMS import refuses a fractional quantity on a whole unit (`WHOLE_UNIT_QUANTITY`); contract becomes v0.3 provisional.
- Existing `RL` is the Roll unit (flagged whole); no separate `ROLL` row.
- A unit referenced by a project request line freezes its factor, like sold or held units; it also counts as used for removal (as do quotation and sales-order lines).
- Existing unit rows keep code and name; the migration only sets their whole-number flag.
- Purchase order summary counts lines received, not mixed units.

## Out of scope

Changing a variant's base unit after creation; merging duplicate units; per-product cut/partial switches.
