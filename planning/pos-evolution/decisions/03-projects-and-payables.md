# Projects and their payables in the POS

**Mode:** domain-model · **Status:** ✅ Locked 2026-11-03 (by: me — user chose A)
**Folds in:** open questions 3 and 4 of [CPMS ↔ POS material-token integration model](../../api-integration/decisions/21-cpms-token-integration-model.md).
**Depends on:** [How approved requests reach the POS](./02-request-transport.md) (CPMS pushes the project with each request).

## Today (verified in source 2026-11-03)

- `Project` (`apps/requisitions/models.py`) has a name, location, dates, and a required `customer` FK to a contractor or construction-firm `Customer`.
- A release (`release_materials`, `apps/requisitions/services.py:166-245`) posts the sale and its `CollectibleLedger` (utang) to **`project.customer`**. The ledger itself has no project field; the project is reachable only through transaction → requisition.
- So receivables today total **per contractor**, not per project.

## Question

When CPMS pushes a project, what is it in the POS, and how does utang show which project owes it?

## Options

- **A. Contractor stays the payer, utang tagged with the project.** `Project` gains a CPMS project id (for matching on later pushes) and keeps its `customer` link; `CollectibleLedger` gains an optional `project` link. Receivables can be read per contractor or per project; one credit limit per contractor.
- **B. Each project is its own customer.** CPMS creates a `Customer` row per project. Utang is per project with no schema change to the ledger, but the same contractor appears once per project and each project gets its own credit limit.
- **C. As today.** Utang only per contractor; the project is found by opening the transaction.

## Recommendation

**A**: matches "the project acts like a customer" for reporting while keeping one real payer and one credit limit; a small migration (two nullable fields).

## Decision

**A. The contractor stays the payer; each utang is tagged with the project.**

| Entity | Change |
|---|---|
| `Project` | + CPMS project id (unique, nullable for legacy rows); a push with a known id updates the same row |
| `CollectibleLedger` | + optional `project` link, set by `release_materials` |
| `Customer` | unchanged; credit limit stays per contractor |

Invariants: a released request's utang always carries its project; walk-in and counter sales carry none. Receivables can total per contractor or per project.
