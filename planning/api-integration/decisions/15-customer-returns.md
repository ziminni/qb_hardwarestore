# Customer Returns

**Mode:** domain-model · **Status:** RESOLVED 2026-10-17 · **Opened:** 2026-10-17
**Phase:** 6 — graduated from [Sales Stack Reconciliation](./05-sales-stack-reconciliation.md), which
deliberately did NOT settle returns and left it on the frontier instead of smuggling it in.

## The question

A customer brings goods back. What IS that, and does it need a new entity or an endpoint?

## What existed, and the trap in the naming

The backend already has a `RETURN` — and it means the **opposite direction**:

```
StockAdjustment.AdjustmentType.RETURN = 'RETURN', 'Return to Supplier'   stock goes OUT, to the vendor
/api/v1/adjustments/   full CRUD, already wired (inventory_service.dart)
SalesTransaction.Source = WALK_IN | REQUISITION    no RETURN member
```

So nothing modelled a **customer** return, and the one similarly-named thing would have moved stock the
wrong way. This is why the question was worth a decision rather than a guess: the obvious reuse
(`RETURN` already exists!) is wrong, and only reading the choice's own label shows it.

## Ruling (user, 2026-10-17)

**A customer return is a `SalesTransaction` with `source='RETURN'` and NEGATIVE amounts**, plus an
**optional `original_transaction` FK** linking back to the sale receipt it reverses.

**The restock rule, settled explicitly:**

- if `original_transaction` is set, returned stock goes back into **the original batch** it left from;
- if it is not, the stock increments **the newest active batch's remaining quantity**.

## Why this over a dedicated entity

The decisive property is that **the reports need no change**. `daily_report/` and every total already
sum `SalesTransaction.grand_total`, so a negative transaction **nets out automatically**. A separate
`SalesReturn` table would have made every one of those sums silently wrong — including refunds it never
knew about — unless each was rewritten as a UNION or a filter, and a forgotten one is a wrong money
figure rather than a visible error.

The alternative of reusing `StockAdjustment` with a new `CUSTOMER_RETURN` choice was rejected because a
stock adjustment **moves no money**: the refund, the receipt and any utang reduction would have had to
live somewhere else anyway, splitting one business event across two features.

## What this costs, stated plainly

- **A migration.** `source` gains a `RETURN` member and `SalesTransaction` gains a nullable
  `original_transaction` FK (PROTECT, so a reversed sale cannot be deleted out from under its return).
  This is the **second** addition to the backend in Phase 6, on top of quotations and orders — the map's
  old "no model or migration changes" invariant is now superseded in three places.
- **A return carries a receipt and a payment like a sale**, which is a modelling choice rather than an
  accident: the refund IS a negative payment on a negative transaction.
- **The restock rule is two rules**, and which one applies depends on a nullable FK. The UI must not
  pretend to know: when there is no original transaction, the cashier is not asked which batch, because
  the answer is "the newest active one" and offering a choice would imply knowledge the system lacks.

## Consequence for the two mock pages

`sales_returns_page.dart` and `inventory_returns_page.dart` both render mock and both become wireable
once the endpoint exists. Whether they **consolidate into one** page or remain two (a sales view and an
inventory view of the same rows) is a UI question for Phase 6, not a domain question — noted here so it
is not silently decided by whichever file happens to be edited first.
