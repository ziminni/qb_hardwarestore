# Historical release amounts after the Phase 1b upgrade

**Mode:** research + grill · **Status:** ✅ Locked (by: me — product owner selected “Preserve history” during Phase 1b planning)
**Depends on:** [When the project starts to owe](./11-when-utang-starts.md), [Request states after Accept](./13-request-states-after-accept.md).

## Verified limitation

`backend_django/apps/requisitions/services.py` `release_materials` records `RequisitionItem.released_qty`, a sale and a project-tagged ledger, but stores no link from that sale to its requisition. `backend_django/apps/pos/models.py` `SalesTransaction` and `SalesItem` have no requisition FK. Several requests can share one project and one material, so neither the project ledger sum nor matching quantities identifies a request's historical release total safely. Audit prose is not a financial relationship.

## Decision

- Preserve all existing requests, sales, ledgers, payments, tokens and audit rows. No flush/reseed is authorised by this plan.
- Existing requests with any `released_qty > 0` have an **unknown** historical released amount. Their `expected_amount` is `null`, displayed as **Expected amount unavailable**, until verified historical totals are supplied in a separately scoped reconciliation.
- Requests with no released quantities start with an exact released amount of `0.00`.
- New releases accumulate the exact persisted sale totals against their request in the same transaction as stock, quantities and debt. A historical unknown stays unknown after a further release; adding a known amount does not make the missing baseline known.
- Never reconstruct old totals from current prices, project totals, timestamps, document-number proximity or audit text. Never use zero to mean unknown.
- This affects only the non-debt expected amount. Project payables keep reading authoritative ledger rows unchanged.

## Implementation route (by: delegated)

Add nullable `Requisition.released_amount` (Decimal, 2dp, ample aggregate precision, default `0.00` for new requests). Migration sets it to `null` on requests with any released quantity, otherwise `0.00`; no historical financial record is rewritten. During a release, add the sale's persisted `grand_total` only when the accumulator is known. The public field is `expected_amount`, not this internal accumulator.

## Alternatives not chosen

- **Reset demo data:** simpler baseline, but destroys existing history and needs explicit dev-only approval.
- **Require reconciliation before upgrade:** preserves exact amounts everywhere, but blocks the upgrade on manual source-record matching.

## Consequence for the contract

Phase 1b v0.2 documents `expected_amount` as a 2-decimal string **or null**, with the historical exception explicit. Missing information is not a zero balance or a failed import. No reconciliation screen, command or guessed backfill is part of Phase 1b.
