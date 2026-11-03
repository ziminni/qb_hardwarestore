# What CPMS sends for each requested item

**Mode:** grill · **Status:** ✅ Locked 2026-11-03 (by: me — user chose B, against the recommended A, and added the out-of-stock requirement)
**Folds in:** open question 5 of [CPMS ↔ POS material-token integration model](../../api-integration/decisions/21-cpms-token-integration-model.md).
**Depends on:** [How approved requests reach the POS](./02-request-transport.md).

## Today (verified in source 2026-11-03)

`RequisitionItem.variant` is a required FK to a POS `ProductVariant` (`apps/requisitions/models.py:111`), and `release_materials` FIFO-deducts that variant. The foreman must not browse POS inventory, so CPMS does not know POS ids unless the POS shares them.

## Question

Each pushed line must end as a POS item the till can release. What does CPMS send, and who turns it into a POS item?

## Options

- **A. CPMS sends free text; the cashier matches at release.** The copy stores "Portland cement 40 kg × 50"; on scan the cashier picks the POS item for each line (search), then releases. Foreman sees nothing of the POS; slower at the till; matching mistakes are human.
- **B. POS publishes a material list CPMS picks from.** The POS exposes a read-only list of item names + codes (no stock, no prices) to the CPMS service account; the PM or foreman picks from it in CPMS, and CPMS sends POS codes. Release stays one scan; reveals the store's item names to CPMS.
- **C. Free text + POS suggests a match.** As A, but the POS pre-fills a best guess (name/barcode similarity) the cashier confirms.

## Recommendation

**A** for now: it keeps the rule that the foreman sees nothing of the POS, needs no new CPMS-facing list, and the cashier already searches the catalogue at the till. The line becomes text plus an optional POS item filled in at release; a release refuses until every line is matched. C can be added later on top of A without changing the data.

## Decision

**B. The POS publishes a material list that CPMS picks from.** The CPMS service account may read a list of active selling units: name, unit, and POS code (the unique per-unit `barcode_qr`, Phase 6). No stock, no prices, no cost. CPMS sends that code and a quantity in that unit for every line; the import refuses an unknown code. Release stays one scan.

**Product-owner requirement added at lock:** at release, a requested item that is out of stock, short, or no longer sold must be handled, not just refused. How is its own decision: [Releasing when stock is short](./05-short-stock-release.md).

## Consequences for the build

- New read-only endpoint for the CPMS service account only; staff accounts keep their existing catalogue endpoints.
- `RequisitionItem` keys on the selling unit (`VariantUOM`) and converts with its `conversion_factor`, the same rule as the till (audit-remediation UOM decision), instead of a bare variant.
- CPMS learns the store's item names; accepted by the product owner.
