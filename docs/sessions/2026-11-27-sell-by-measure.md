# Sell by measure — 2026-11-27

Branch `feat/sell-by-measure` (from master `1a796fdc`) in the Windows QA clone
`DEVELOPMENT_FOLDER/hardware_store_qa`. Design and plan:
`planning/sell-in-parts/2026-11-27-sell-by-measure-design.md` and `-plan.md`.

## What changed

- **Backend:** quantities stored to 6 decimals (`common.fields.QuantityField`,
  read back trimmed so the API still prints `"10.00"`, which CPMS relies on).
  New `VariantUOM.measure_per_base` and `POST /variants/{id}/add-measure-unit/`.
  Sales, returns, voids, held carts, transfers, releases, adjustments and
  reports convert with `common.quantities.to_base_qty` (divide by kilos per
  bag). FIFO sweeps rounding dust (`measure_tolerance`). Typed quantities are
  refused beyond 2 decimals (`QTY_TOO_PRECISE`). Migrations: bodega 0005,
  inventory 0029, pos 0029, requisitions 0004.
- **Flutter:** stock reads "9 BAG + 30 KG" (stock table, low stock, product
  details); POS kilo/metre cards show exact kilos/metres left; "Add selling
  unit" (renamed from "Add pack unit") has a third tab **By weight or length**;
  Add Product has a **Sell loose** section (½, ¼, by weight or length) when
  the base unit is whole; till and returns quantity inputs take at most 2
  decimals; Adjust Stock can count an opened bag in kilos.

## Verification

- Backend full suite on throwaway Postgres (`qbt_db2`): 1,815 tests OK.
- Flutter: new tests green (measure format, POS measure, unit dialog, Sell
  loose, adjust in KG, create-chain routing). Full-suite comparison against
  master recorded in the branch ledger.
- Not yet done: clicking the flows in a rebuilt QA app against the throwaway
  stack. No production database was touched; nothing pushed.
